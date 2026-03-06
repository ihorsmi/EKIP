from __future__ import annotations

import logging
from typing import Protocol

from core.config import settings
from core.store import StateStore
from core.vector_store import RetrievedChunk
from orchestrator.maf_orchestrator import AgentFrameworkOrchestrator
from orchestrator.orchestrator import Orchestrator

logger = logging.getLogger(__name__)


class OrchestratorLike(Protocol):
    def answer(
        self, *, question: str, conversation_id: str | None
    ) -> tuple[str, str, list[RetrievedChunk], list[str]]: ...


def build_orchestrator(store: StateStore) -> OrchestratorLike:
    mode = settings.orchestrator_mode.lower().strip()
    if mode == "deterministic":
        return Orchestrator(store)
    if mode == "maf":
        return AgentFrameworkOrchestrator(store)

    logger.warning("unknown_orchestrator_mode_fallback", extra={"mode": settings.orchestrator_mode})
    return Orchestrator(store)
