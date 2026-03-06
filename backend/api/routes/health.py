from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter

from core.schemas import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", time_utc=datetime.now(timezone.utc))
