from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from api.auth import AuthContext, require_role
from api.deps import get_store
from core.schemas import ConversationHistoryResponse, ConversationSummary, Message
from core.store import StateStore

router = APIRouter()


@router.get("/history/{conversation_id}", response_model=ConversationHistoryResponse)
def get_history(
    conversation_id: str,
    store: StateStore = Depends(get_store),
    _auth: AuthContext = Depends(require_role("Admin", "Analyst", "Viewer")),
) -> ConversationHistoryResponse:
    convo = store.get_conversation(conversation_id)
    if not convo:
        raise HTTPException(status_code=404, detail="Conversation not found.")
    messages = store.get_messages(conversation_id, limit=200)
    return ConversationHistoryResponse(
        conversation=ConversationSummary(
            conversation_id=convo.conversation_id,
            created_at=convo.created_at,
            title=convo.title,
        ),
        messages=[Message(role=m.role, content=m.content, created_at=m.created_at) for m in messages],
    )


@router.get("/history", response_model=list[ConversationSummary])
def list_conversations(
    store: StateStore = Depends(get_store),
    _auth: AuthContext = Depends(require_role("Admin", "Analyst", "Viewer")),
    limit: int = 20,
) -> list[ConversationSummary]:
    rows = store.list_conversations(limit=limit)
    return [
        ConversationSummary(conversation_id=r.conversation_id, created_at=r.created_at, title=r.title)
        for r in rows
    ]
