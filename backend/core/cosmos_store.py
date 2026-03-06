from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from azure.cosmos import CosmosClient, PartitionKey
from azure.identity import DefaultAzureCredential

from core.db import ConversationRow, IngestJobRow, MessageRow

logger = logging.getLogger(__name__)


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class CosmosStore:
    """Cosmos DB implementation for app state and audit logs.

    Container layout:
    - conversations: conversation docs + message docs (partition key: /pk => conversation_id)
    - ingest_jobs: ingest job docs (partition key: /pk => job_id)
    - agent_logs: agent event docs (partition key: /pk => conversation_id or "system")
    """

    def __init__(
        self,
        *,
        endpoint: str,
        key: str,
        database_name: str,
        conversations_container: str,
        ingest_jobs_container: str,
        agent_logs_container: str,
    ) -> None:
        if not endpoint:
            raise ValueError("AZURE_COSMOS_ENDPOINT is required for EKIP_STATE_PROVIDER=cosmos")

        self.endpoint = endpoint
        self.key = key.strip()
        self.database_name = database_name
        self.conversations_container = conversations_container
        self.ingest_jobs_container = ingest_jobs_container
        self.agent_logs_container = agent_logs_container

        if self.key:
            self._client = CosmosClient(self.endpoint, credential=self.key)
        else:
            self._client = CosmosClient(self.endpoint, credential=DefaultAzureCredential())

        self._db = None
        self._conv = None
        self._jobs = None
        self._logs = None

    def migrate(self) -> None:
        self._db = self._client.create_database_if_not_exists(id=self.database_name)
        self._conv = self._db.create_container_if_not_exists(
            id=self.conversations_container,
            partition_key=PartitionKey(path="/pk"),
            offer_throughput=400,
        )
        self._jobs = self._db.create_container_if_not_exists(
            id=self.ingest_jobs_container,
            partition_key=PartitionKey(path="/pk"),
            offer_throughput=400,
        )
        self._logs = self._db.create_container_if_not_exists(
            id=self.agent_logs_container,
            partition_key=PartitionKey(path="/pk"),
            offer_throughput=400,
        )
        logger.info(
            "cosmos_migrated",
            extra={
                "db": self.database_name,
                "conversations_container": self.conversations_container,
                "ingest_jobs_container": self.ingest_jobs_container,
                "agent_logs_container": self.agent_logs_container,
            },
        )

    def _require_init(self) -> tuple[Any, Any, Any]:
        if self._conv is None or self._jobs is None or self._logs is None:
            self.migrate()
        return self._conv, self._jobs, self._logs

    # ---- Conversations ----

    def create_conversation(self, title: str) -> str:
        conversation_id = str(uuid.uuid4())
        self.upsert_conversation(conversation_id, title=title)
        return conversation_id

    def upsert_conversation(self, conversation_id: str, title: str) -> None:
        conv, _, _ = self._require_init()
        item = {
            "id": f"conv::{conversation_id}",
            "pk": conversation_id,
            "type": "conversation",
            "conversation_id": conversation_id,
            "title": title,
            "created_at": _utcnow_iso(),
        }
        conv.upsert_item(item)

    def add_message(self, conversation_id: str, role: str, content: str) -> None:
        conv, _, _ = self._require_init()
        item = {
            "id": f"msg::{uuid.uuid4()}",
            "pk": conversation_id,
            "type": "message",
            "conversation_id": conversation_id,
            "role": role,
            "content": content,
            "created_at": _utcnow_iso(),
        }
        conv.upsert_item(item)

    def get_conversation(self, conversation_id: str) -> ConversationRow | None:
        conv, _, _ = self._require_init()
        query = (
            "SELECT TOP 1 c.conversation_id, c.title, c.created_at "
            "FROM c WHERE c.type='conversation' AND c.conversation_id=@conversation_id"
        )
        rows = list(
            conv.query_items(
                query=query,
                parameters=[{"name": "@conversation_id", "value": conversation_id}],
                partition_key=conversation_id,
            )
        )
        if not rows:
            return None
        row = rows[0]
        return ConversationRow(
            conversation_id=row["conversation_id"],
            title=row["title"],
            created_at=datetime.fromisoformat(row["created_at"]),
        )

    def get_messages(self, conversation_id: str, limit: int = 50) -> list[MessageRow]:
        conv, _, _ = self._require_init()
        query = (
            f"SELECT TOP {int(limit)} c.role, c.content, c.created_at "
            "FROM c WHERE c.type='message' AND c.conversation_id=@conversation_id "
            "ORDER BY c.created_at ASC"
        )
        rows = list(
            conv.query_items(
                query=query,
                parameters=[{"name": "@conversation_id", "value": conversation_id}],
                partition_key=conversation_id,
            )
        )
        return [
            MessageRow(
                role=r["role"],
                content=r["content"],
                created_at=datetime.fromisoformat(r["created_at"]),
            )
            for r in rows
        ]

    def list_conversations(self, limit: int = 20) -> list[ConversationRow]:
        conv, _, _ = self._require_init()
        query = (
            f"SELECT TOP {int(limit)} c.conversation_id, c.title, c.created_at "
            "FROM c WHERE c.type='conversation' ORDER BY c.created_at DESC"
        )
        rows = list(
            conv.query_items(
                query=query,
                enable_cross_partition_query=True,
            )
        )
        return [
            ConversationRow(
                conversation_id=r["conversation_id"],
                title=r["title"],
                created_at=datetime.fromisoformat(r["created_at"]),
            )
            for r in rows
        ]

    # ---- Ingest jobs ----

    def create_ingest_job(self, filename: str, metadata_json: str = "{}") -> str:
        _, jobs, _ = self._require_init()
        job_id = str(uuid.uuid4())
        now = _utcnow_iso()
        jobs.upsert_item(
            {
                "id": f"job::{job_id}",
                "pk": job_id,
                "job_id": job_id,
                "filename": filename,
                "status": "queued",
                "error": None,
                "chunks_indexed": 0,
                "metadata_json": metadata_json,
                "created_at": now,
                "updated_at": now,
            }
        )
        return job_id

    def update_ingest_job(
        self,
        job_id: str,
        status: str,
        *,
        error: str | None = None,
        chunks_indexed: int | None = None,
        metadata_json: str | None = None,
    ) -> None:
        _, jobs, _ = self._require_init()
        row = self.get_ingest_job(job_id)
        if row is None:
            # Keep behavior close to sqlite: no-op if missing.
            return
        payload = {
            "id": f"job::{job_id}",
            "pk": job_id,
            "job_id": job_id,
            "filename": row.filename,
            "status": status,
            "error": error if error is not None else row.error,
            "chunks_indexed": chunks_indexed if chunks_indexed is not None else row.chunks_indexed,
            "metadata_json": metadata_json if metadata_json is not None else row.metadata_json,
            "created_at": row.created_at.isoformat(),
            "updated_at": _utcnow_iso(),
        }
        jobs.upsert_item(payload)

    def get_ingest_job(self, job_id: str) -> IngestJobRow | None:
        _, jobs, _ = self._require_init()
        query = (
            "SELECT TOP 1 c.job_id, c.filename, c.status, c.error, c.chunks_indexed, c.created_at, c.updated_at, c.metadata_json "
            "FROM c WHERE c.job_id=@job_id"
        )
        rows = list(
            jobs.query_items(
                query=query,
                parameters=[{"name": "@job_id", "value": job_id}],
                partition_key=job_id,
            )
        )
        if not rows:
            return None
        r = rows[0]
        return IngestJobRow(
            job_id=r["job_id"],
            filename=r["filename"],
            status=r["status"],
            error=r.get("error"),
            chunks_indexed=int(r.get("chunks_indexed", 0)),
            created_at=datetime.fromisoformat(r["created_at"]),
            updated_at=datetime.fromisoformat(r["updated_at"]),
            metadata_json=r.get("metadata_json", "{}"),
        )

    def list_ingest_jobs(self, limit: int = 50) -> list[IngestJobRow]:
        _, jobs, _ = self._require_init()
        query = (
            f"SELECT TOP {int(limit)} c.job_id, c.filename, c.status, c.error, c.chunks_indexed, c.created_at, c.updated_at, c.metadata_json "
            "FROM c ORDER BY c.created_at DESC"
        )
        rows = list(
            jobs.query_items(
                query=query,
                enable_cross_partition_query=True,
            )
        )
        out: list[IngestJobRow] = []
        for r in rows:
            out.append(
                IngestJobRow(
                    job_id=r["job_id"],
                    filename=r["filename"],
                    status=r["status"],
                    error=r.get("error"),
                    chunks_indexed=int(r.get("chunks_indexed", 0)),
                    created_at=datetime.fromisoformat(r["created_at"]),
                    updated_at=datetime.fromisoformat(r["updated_at"]),
                    metadata_json=r.get("metadata_json", "{}"),
                )
            )
        return out

    # ---- Agent logs ----

    def log_agent_event(
        self,
        *,
        conversation_id: str | None,
        agent: str,
        event: str,
        payload_json: str = "{}",
    ) -> None:
        _, _, logs = self._require_init()
        try:
            payload = json.loads(payload_json) if payload_json else {}
        except Exception:
            payload = {"raw_payload": payload_json}
        logs.upsert_item(
            {
                "id": f"log::{uuid.uuid4()}",
                "pk": conversation_id or "system",
                "conversation_id": conversation_id,
                "agent": agent,
                "event": event,
                "payload": payload,
                "created_at": _utcnow_iso(),
            }
        )
