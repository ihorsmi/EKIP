from __future__ import annotations

import logging
from typing import List

from core.config import settings
from core.exceptions import RetrievalError
from core.providers import build_vector_store
from core.vector_store import RetrievedChunk, VectorStore
from rag.embedder import embed_texts

logger = logging.getLogger(__name__)


class Retriever:
    def __init__(self, store: VectorStore | None = None) -> None:
        self.store = store or build_vector_store()

    def retrieve(self, query: str, *, limit: int = 6) -> List[RetrievedChunk]:
        try:
            [q_emb] = embed_texts([query])
            self.store.ensure()
            # AzureSearchStore supports hybrid; Qdrant ignores query_text (vector-only).
            if settings.index_provider.lower().strip() in ("azuresearch", "search", "ai-search"):
                # type: ignore[attr-defined]
                return self.store.search(q_emb, limit=limit, query_text=query)  # pyright: ignore
            return self.store.search(q_emb, limit=limit)
        except Exception as exc:  # noqa: BLE001
            logger.exception("retrieval_failed")
            raise RetrievalError(f"Retrieval failed: {exc}") from exc
