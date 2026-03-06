from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException
from starlette.status import HTTP_400_BAD_REQUEST, HTTP_500_INTERNAL_SERVER_ERROR

from api.auth import AuthContext, require_role
from api.deps import get_store
from core.schemas import Citation, QueryRequest, QueryResponse
from core.store import StateStore
from orchestrator.factory import build_orchestrator

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/query", response_model=QueryResponse)
def query(
    req: QueryRequest,
    store: StateStore = Depends(get_store),
    auth: AuthContext = Depends(require_role("Admin", "Analyst", "Viewer")),
) -> QueryResponse:
    if not req.question.strip():
        raise HTTPException(status_code=HTTP_400_BAD_REQUEST, detail="Question cannot be empty.")

    try:
        orchestrator = build_orchestrator(store)
        conversation_id, answer, chunks, actions = orchestrator.answer(
            question=req.question, conversation_id=req.conversation_id
        )
        citations = [
            Citation(
                doc_id=c.doc_id,
                filename=c.filename,
                chunk_index=c.chunk_index,
                score=c.score,
                text=c.text,
            )
            for c in chunks
        ]
        return QueryResponse(
            conversation_id=conversation_id,
            answer=answer,
            citations=citations,
            actions=actions,
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("query_failed", extra={"user_id": auth.user_id})
        raise HTTPException(status_code=HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc)) from exc
