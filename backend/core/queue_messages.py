from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict


def utcnow_iso() -> str:
    """Return ISO8601 UTC timestamp with Z suffix (e.g., 2026-02-23T13:21:31Z)."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


@dataclass(frozen=True)
class IngestDocumentMessage:
    """Queue message schema for document ingestion.

    This matches data/queue_messages/ingest_document_message.schema.json in the data pack.
    Keep it stable so Redis <-> Service Bus is a 1:1 swap.
    """

    doc_id: str
    blob_url: str
    filename: str
    content_type: str
    uploaded_by: str
    uploaded_at: str
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_json(self) -> str:
        return json.dumps(
            {
                "doc_id": self.doc_id,
                "blob_url": self.blob_url,
                "filename": self.filename,
                "content_type": self.content_type,
                "uploaded_by": self.uploaded_by,
                "uploaded_at": self.uploaded_at,
                "metadata": self.metadata or {},
            },
            ensure_ascii=False,
        )

    @staticmethod
    def from_json(raw: str) -> "IngestDocumentMessage":
        obj = json.loads(raw)
        return IngestDocumentMessage(
            doc_id=str(obj["doc_id"]),
            blob_url=str(obj["blob_url"]),
            filename=str(obj["filename"]),
            content_type=str(obj.get("content_type") or "application/octet-stream"),
            uploaded_by=str(obj.get("uploaded_by") or "unknown"),
            uploaded_at=str(obj.get("uploaded_at") or utcnow_iso()),
            metadata=dict(obj.get("metadata") or {}),
        )
