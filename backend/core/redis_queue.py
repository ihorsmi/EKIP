from __future__ import annotations

import logging
from typing import Callable, Optional

import redis

from core.queue_messages import IngestDocumentMessage
from core.queue_provider import QueueProvider

logger = logging.getLogger(__name__)


class RedisQueue(QueueProvider):
    """Redis-backed queue for local dev.

    Queue message schema is identical to Azure Service Bus to enable a 1:1 swap later.
    """

    def __init__(self, redis_url: str, queue_name: str) -> None:
        self._client = redis.Redis.from_url(redis_url, decode_responses=True)
        self.queue_name = queue_name

    def ping(self) -> bool:
        return bool(self._client.ping())

    def enqueue(self, message: IngestDocumentMessage) -> None:
        self._client.rpush(self.queue_name, message.to_json())
        logger.info("ingest_enqueued", extra={"doc_id": message.doc_id, "provider": "redis"})

    def process_one(self, handler: Callable[[IngestDocumentMessage], None], *, timeout_seconds: int = 10) -> bool:
        # BLPOP returns (queue, item) or None
        item = self._client.blpop(self.queue_name, timeout=timeout_seconds)
        if not item:
            return False

        _, raw = item
        try:
            message = IngestDocumentMessage.from_json(raw)
        except Exception:  # noqa: BLE001
            logger.exception("redis_message_decode_failed", extra={"raw": raw})
            # Drop malformed item to prevent infinite loop
            return True

        try:
            handler(message)
            return True
        except Exception:  # noqa: BLE001
            # Redis BLPOP removes the item immediately; we can't "abandon".
            # Failures can be captured for replay in higher-level retry workflows.
            logger.exception("redis_handler_failed", extra={"doc_id": message.doc_id})
            return True

