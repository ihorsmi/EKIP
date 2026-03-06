from __future__ import annotations

from fastapi import Request

from core.blob_store import BlobStore
from core.queue_provider import QueueProvider
from core.store import StateStore


def get_store(request: Request) -> StateStore:
    return request.app.state.store  # type: ignore[attr-defined]


def get_queue(request: Request) -> QueueProvider:
    return request.app.state.queue  # type: ignore[attr-defined]


def get_blob_store(request: Request) -> BlobStore:
    return request.app.state.blob_store  # type: ignore[attr-defined]
