from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: Literal["ok"]
    service: str = "ekip-backend"
    time_utc: datetime


class UploadResponse(BaseModel):
    job_id: str
    filename: str
    status: str


class QueryRequest(BaseModel):
    question: str = Field(min_length=1, max_length=4000)
    conversation_id: Optional[str] = None


class Citation(BaseModel):
    doc_id: str
    filename: str
    chunk_index: int
    score: float
    text: str


class QueryResponse(BaseModel):
    conversation_id: str
    answer: str
    citations: List[Citation] = Field(default_factory=list)
    actions: List[str] = Field(default_factory=list)


class ConversationSummary(BaseModel):
    conversation_id: str
    created_at: datetime
    title: str


class Message(BaseModel):
    role: Literal["user", "assistant"]
    content: str
    created_at: datetime


class ConversationHistoryResponse(BaseModel):
    conversation: ConversationSummary
    messages: List[Message]


class IngestJob(BaseModel):
    job_id: str
    filename: str
    status: str
    error: Optional[str] = None
    chunks_indexed: int = 0
    created_at: datetime
    updated_at: datetime
    metadata: Dict[str, Any] = Field(default_factory=dict)
