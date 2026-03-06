from __future__ import annotations

import logging
import sqlite3
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

logger = logging.getLogger(__name__)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass(frozen=True)
class ConversationRow:
    conversation_id: str
    created_at: datetime
    title: str


@dataclass(frozen=True)
class MessageRow:
    role: str
    content: str
    created_at: datetime


@dataclass(frozen=True)
class IngestJobRow:
    job_id: str
    filename: str
    status: str
    error: Optional[str]
    chunks_indexed: int
    created_at: datetime
    updated_at: datetime
    metadata_json: str


class SqliteStore:
    """SQLite store for non-Azure development and tests.

    Production deployments use CosmosStore through the same interface.
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def connect(self) -> Iterable[sqlite3.Connection]:
        conn = sqlite3.connect(str(self.path))
        try:
            conn.row_factory = sqlite3.Row
            yield conn
            conn.commit()
        finally:
            conn.close()

    def migrate(self) -> None:
        with self.connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS conversations (
                    conversation_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS messages (
                    message_id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id)
                );
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS ingest_jobs (
                    job_id TEXT PRIMARY KEY,
                    filename TEXT NOT NULL,
                    status TEXT NOT NULL,
                    error TEXT,
                    chunks_indexed INTEGER NOT NULL DEFAULT 0,
                    metadata_json TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS agent_logs (
                    event_id TEXT PRIMARY KEY,
                    conversation_id TEXT,
                    agent TEXT NOT NULL,
                    event TEXT NOT NULL,
                    payload_json TEXT NOT NULL DEFAULT '{}',
                    created_at TEXT NOT NULL
                );
                """
            )
        logger.info("sqlite_migrated", extra={"db_path": str(self.path)})

    # ---- Conversations ----

    def create_conversation(self, title: str) -> str:
        conversation_id = str(uuid.uuid4())
        with self.connect() as conn:
            conn.execute(
                "INSERT INTO conversations (conversation_id, title, created_at) VALUES (?, ?, ?)",
                (conversation_id, title, utcnow().isoformat()),
            )
        return conversation_id

    def upsert_conversation(self, conversation_id: str, title: str) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO conversations (conversation_id, title, created_at)
                VALUES (?, ?, ?)
                ON CONFLICT(conversation_id) DO UPDATE SET title=excluded.title
                """,
                (conversation_id, title, utcnow().isoformat()),
            )

    def add_message(self, conversation_id: str, role: str, content: str) -> None:
        message_id = str(uuid.uuid4())
        with self.connect() as conn:
            conn.execute(
                "INSERT INTO messages (message_id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)",
                (message_id, conversation_id, role, content, utcnow().isoformat()),
            )

    def get_conversation(self, conversation_id: str) -> Optional[ConversationRow]:
        with self.connect() as conn:
            row = conn.execute(
                "SELECT conversation_id, title, created_at FROM conversations WHERE conversation_id=?",
                (conversation_id,),
            ).fetchone()
        if not row:
            return None
        return ConversationRow(
            conversation_id=row["conversation_id"],
            title=row["title"],
            created_at=datetime.fromisoformat(row["created_at"]),
        )

    def get_messages(self, conversation_id: str, limit: int = 50) -> List[MessageRow]:
        with self.connect() as conn:
            rows = conn.execute(
                """
                SELECT role, content, created_at
                FROM messages
                WHERE conversation_id=?
                ORDER BY created_at ASC
                LIMIT ?
                """,
                (conversation_id, limit),
            ).fetchall()
        out: List[MessageRow] = []
        for r in rows:
            out.append(
                MessageRow(
                    role=r["role"],
                    content=r["content"],
                    created_at=datetime.fromisoformat(r["created_at"]),
                )
            )
        return out


    def list_conversations(self, limit: int = 20) -> List[ConversationRow]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT conversation_id, title, created_at FROM conversations ORDER BY created_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        out: List[ConversationRow] = []
        for r in rows:
            out.append(
                ConversationRow(
                    conversation_id=r["conversation_id"],
                    title=r["title"],
                    created_at=datetime.fromisoformat(r["created_at"]),
                )
            )
        return out

    # ---- Ingest jobs ----

    def create_ingest_job(self, filename: str, metadata_json: str = "{}") -> str:
        job_id = str(uuid.uuid4())
        now = utcnow().isoformat()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO ingest_jobs (job_id, filename, status, error, chunks_indexed, metadata_json, created_at, updated_at)
                VALUES (?, ?, 'queued', NULL, 0, ?, ?, ?)
                """,
                (job_id, filename, metadata_json, now, now),
            )
        return job_id

    def update_ingest_job(
        self,
        job_id: str,
        status: str,
        *,
        error: Optional[str] = None,
        chunks_indexed: Optional[int] = None,
        metadata_json: Optional[str] = None,
    ) -> None:
        fields: List[str] = ["status=?", "updated_at=?"]
        params: List[Any] = [status, utcnow().isoformat()]

        if error is not None:
            fields.append("error=?")
            params.append(error)
        if chunks_indexed is not None:
            fields.append("chunks_indexed=?")
            params.append(chunks_indexed)
        if metadata_json is not None:
            fields.append("metadata_json=?")
            params.append(metadata_json)

        params.append(job_id)

        with self.connect() as conn:
            conn.execute(f"UPDATE ingest_jobs SET {', '.join(fields)} WHERE job_id=?", params)

    def get_ingest_job(self, job_id: str) -> Optional[IngestJobRow]:
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT job_id, filename, status, error, chunks_indexed, created_at, updated_at, metadata_json
                FROM ingest_jobs WHERE job_id=?
                """,
                (job_id,),
            ).fetchone()
        if not row:
            return None
        return IngestJobRow(
            job_id=row["job_id"],
            filename=row["filename"],
            status=row["status"],
            error=row["error"],
            chunks_indexed=int(row["chunks_indexed"]),
            created_at=datetime.fromisoformat(row["created_at"]),
            updated_at=datetime.fromisoformat(row["updated_at"]),
            metadata_json=row["metadata_json"],
        )

    def list_ingest_jobs(self, limit: int = 50) -> List[IngestJobRow]:
        with self.connect() as conn:
            rows = conn.execute(
                """
                SELECT job_id, filename, status, error, chunks_indexed, created_at, updated_at, metadata_json
                FROM ingest_jobs
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        out: List[IngestJobRow] = []
        for row in rows:
            out.append(
                IngestJobRow(
                    job_id=row["job_id"],
                    filename=row["filename"],
                    status=row["status"],
                    error=row["error"],
                    chunks_indexed=int(row["chunks_indexed"]),
                    created_at=datetime.fromisoformat(row["created_at"]),
                    updated_at=datetime.fromisoformat(row["updated_at"]),
                    metadata_json=row["metadata_json"],
                )
            )
        return out

    def log_agent_event(
        self,
        *,
        conversation_id: str | None,
        agent: str,
        event: str,
        payload_json: str = "{}",
    ) -> None:
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO agent_logs (event_id, conversation_id, agent, event, payload_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (str(uuid.uuid4()), conversation_id, agent, event, payload_json, utcnow().isoformat()),
            )

