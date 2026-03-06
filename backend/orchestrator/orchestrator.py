from __future__ import annotations

import json
import logging
from typing import List, Tuple

from agents.advisor import advise
from agents.reasoner import ReasonerAgent
from agents.summarizer import summarize
from core.store import StateStore
from core.vector_store import RetrievedChunk

logger = logging.getLogger(__name__)


class Orchestrator:
    """Coordinates agents in a predictable, testable way."""

    def __init__(self, store: StateStore) -> None:
        self.store = store
        self.reasoner = ReasonerAgent()

    def answer(self, *, question: str, conversation_id: str | None) -> Tuple[str, str, List[RetrievedChunk], List[str]]:
        # Ensure conversation exists
        if not conversation_id:
            conversation_id = self.store.create_conversation(title="EKIP Chat")
        else:
            existing = self.store.get_conversation(conversation_id)
            if not existing:
                self.store.upsert_conversation(conversation_id, title="EKIP Chat")

        self.store.add_message(conversation_id, role="user", content=question)
        self.store.log_agent_event(
            conversation_id=conversation_id,
            agent="orchestrator",
            event="question_received",
            payload_json=json.dumps({"question": question}),
        )

        chunks = self.reasoner.get_context(question, limit=6)
        self.store.log_agent_event(
            conversation_id=conversation_id,
            agent="reasoner",
            event="context_retrieved",
            payload_json=json.dumps({"chunks": len(chunks)}),
        )
        answer = summarize(question, chunks)
        self.store.log_agent_event(
            conversation_id=conversation_id,
            agent="summarizer",
            event="answer_generated",
            payload_json=json.dumps({"answer_length": len(answer)}),
        )
        actions = advise(question, answer, chunks)
        self.store.log_agent_event(
            conversation_id=conversation_id,
            agent="advisor",
            event="actions_generated",
            payload_json=json.dumps({"action_count": len(actions)}),
        )

        self.store.add_message(conversation_id, role="assistant", content=answer)

        logger.info("query_answered", extra={"conversation_id": conversation_id, "chunks": len(chunks)})
        return conversation_id, answer, chunks, actions

