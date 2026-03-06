from __future__ import annotations

from fastapi import APIRouter

from api.routes.health import router as health_router
from api.routes.upload import router as upload_router
from api.routes.query import router as query_router
from api.routes.history import router as history_router

# Canonical API router imported by main.py
api_router = APIRouter()

api_router.include_router(health_router, tags=["health"])
api_router.include_router(upload_router, tags=["upload"])
api_router.include_router(query_router, tags=["query"])
api_router.include_router(history_router, tags=["history"])
