from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.middleware import CorrelationIdMiddleware
from api.router import api_router
from core.config import settings
from core.logging import setup_logging
from core.providers import build_blob_store, build_queue, build_state_store

load_dotenv()
setup_logging(settings.log_level)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings.ensure_dirs()

    app.state.store = build_state_store()
    app.state.store.migrate()
    app.state.queue = build_queue()
    app.state.blob_store = build_blob_store()

    logger.info(
        "backend_started",
        extra={
            "env": settings.ekip_env,
            "state_provider": settings.state_provider,
            "queue_provider": settings.queue_provider,
            "storage_provider": settings.storage_provider,
            "index_provider": settings.index_provider,
        },
    )
    yield
    logger.info("backend_stopped")


app = FastAPI(
    title="EKIP Backend",
    version="0.2.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-ID", "X-Correlation-ID"],
)
app.add_middleware(CorrelationIdMiddleware)
app.include_router(api_router)
