from __future__ import annotations

import logging
import uuid
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

from core.config import settings
from core.exceptions import IngestionError
from core.providers import build_vector_store
from core.vector_store import VectorStore
from rag.chunker import chunk_text
from rag.embedder import embed_texts

logger = logging.getLogger(__name__)


def _read_txt(path: Path) -> str:
    data = path.read_bytes()
    for enc in ("utf-8", "utf-16", "latin-1"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def _read_pdf(path: Path) -> str:
    from pypdf import PdfReader  # lazy import

    reader = PdfReader(str(path))
    parts: List[str] = []
    for page in reader.pages:
        parts.append(page.extract_text() or "")
    return "\n".join(parts)


def _read_docx(path: Path) -> str:
    import docx  # type: ignore  # lazy import

    doc = docx.Document(str(path))
    parts: List[str] = [p.text for p in doc.paragraphs if p.text]
    return "\n".join(parts)


def read_document(path: Path) -> str:
    ext = path.suffix.lower().lstrip(".")
    if ext in ("txt", "md", "csv", "log"):
        return _read_txt(path)
    if ext in ("pdf",):
        return _read_pdf(path)
    if ext in ("docx",):
        return _read_docx(path)
    return _read_txt(path)


class IngestorAgent:
    """Agent 1 - Ingestor: parse -> chunk -> embed -> vector store.

    Storage and queue are handled elsewhere. This agent focuses on turning a local file into chunks
    and pushing them into the configured VectorStore (Qdrant or Azure AI Search).
    """

    def __init__(self, store: VectorStore | None = None) -> None:
        self.store = store or build_vector_store()

    def ingest(self, *, file_path: str, filename: str, doc_id: str | None = None) -> Tuple[str, int]:
        """Ingest a document and return (doc_id, chunks_indexed)."""
        doc_id = doc_id or str(uuid.uuid4())
        try:
            path = Path(file_path)
            if not path.exists():
                raise IngestionError(f"File does not exist: {file_path}")

            text = read_document(path)
            chunks = chunk_text(text)
            if not chunks:
                raise IngestionError("No text could be extracted from the document.")

            embeddings: Sequence[Sequence[float]] = embed_texts([c.text for c in chunks])

            # Ensure index/collection exists (idempotent)
            self.store.ensure()
            payloads: List[Dict[str, Any]] = []
            for c in chunks:
                payloads.append(
                    {
                        "doc_id": doc_id,
                        "filename": filename,
                        "chunk_index": c.index,
                        "text": c.text,
                    }
                )

            count = self.store.upsert_chunks(embeddings=embeddings, payloads=payloads)
            logger.info(
                "document_ingested",
                extra={"doc_id": doc_id, "chunks_indexed": count, "index_provider": settings.index_provider},
            )
            return doc_id, count
        except Exception as exc:  # noqa: BLE001
            # Avoid reserved LogRecord attribute names in "extra" (e.g., "filename").
            logger.exception("ingestion_failed", extra={"source_filename": filename, "doc_id": doc_id})
            if isinstance(exc, IngestionError):
                raise
            raise IngestionError(str(exc)) from exc

