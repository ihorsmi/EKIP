from __future__ import annotations

from typing import Protocol

from core.db import ConversationRow, IngestJobRow, MessageRow


class StateStore(Protocol):
    """Persistence contract used by API + worker.

    Implementations:
    - SqliteStore: local dev
    - CosmosStore: Azure-backed state/audit
    """

    def migrate(self) -> None: ...

    def create_conversation(self, title: str) -> str: ...
    def upsert_conversation(self, conversation_id: str, title: str) -> None: ...
    def add_message(self, conversation_id: str, role: str, content: str) -> None: ...
    def get_conversation(self, conversation_id: str) -> ConversationRow | None: ...
    def get_messages(self, conversation_id: str, limit: int = 50) -> list[MessageRow]: ...
    def list_conversations(self, limit: int = 20) -> list[ConversationRow]: ...

    def create_ingest_job(self, filename: str, metadata_json: str = "{}") -> str: ...
    def update_ingest_job(
        self,
        job_id: str,
        status: str,
        *,
        error: str | None = None,
        chunks_indexed: int | None = None,
        metadata_json: str | None = None,
    ) -> None: ...
    def get_ingest_job(self, job_id: str) -> IngestJobRow | None: ...
    def list_ingest_jobs(self, limit: int = 50) -> list[IngestJobRow]: ...

    def log_agent_event(
        self,
        *,
        conversation_id: str | None,
        agent: str,
        event: str,
        payload_json: str = "{}",
    ) -> None: ...
