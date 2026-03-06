from __future__ import annotations

import logging
from typing import List

from core.vector_store import RetrievedChunk
from rag.retriever import Retriever

logger = logging.getLogger(__name__)


class ReasonerAgent:
    """Agent 2 - Reasoner: retrieve and rank grounding context."""

    def __init__(self) -> None:
        self.retriever = Retriever()

    def get_context(self, question: str, *, limit: int = 6) -> List[RetrievedChunk]:
        chunks = self.retriever.retrieve(question, limit=limit)
        logger.info("context_retrieved", extra={"chunks": len(chunks)})
        return chunks

