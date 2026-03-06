from __future__ import annotations

import logging
from typing import Callable, Optional
from urllib.parse import urlparse

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage

from core.queue_messages import IngestDocumentMessage
from core.queue_provider import QueueProvider

logger = logging.getLogger(__name__)


class ServiceBusQueue(QueueProvider):
    """Azure Service Bus queue provider.

    Supports:
    - Connection string (local dev): AZURE_SERVICEBUS_CONNECTION_STRING
    - Managed identity (Azure): AZURE_SERVICEBUS_FQDN + DefaultAzureCredential
    """

    def __init__(self, *, connection_string: str, fully_qualified_namespace: str, queue_name: str) -> None:
        self._connection_string = connection_string.strip()
        self._fqns = fully_qualified_namespace.strip()
        self._queue_name = queue_name

        if not self._queue_name:
            raise ValueError("Service Bus queue name is required")

        if not self._connection_string and not self._fqns:
            raise ValueError("Provide AZURE_SERVICEBUS_CONNECTION_STRING or AZURE_SERVICEBUS_FQDN")

    def _client(self) -> ServiceBusClient:
        if self._connection_string:
            return ServiceBusClient.from_connection_string(self._connection_string)
        # Managed identity path
        return ServiceBusClient(self._fqns, credential=DefaultAzureCredential())

    def enqueue(self, message: IngestDocumentMessage) -> None:
        body = message.to_json()
        sb_msg = ServiceBusMessage(body, content_type="application/json", subject="ekip.ingest")
        with self._client() as client:
            with client.get_queue_sender(queue_name=self._queue_name) as sender:
                sender.send_messages(sb_msg)
        logger.info("ingest_enqueued", extra={"doc_id": message.doc_id, "provider": "servicebus"})

    def process_one(self, handler: Callable[[IngestDocumentMessage], None], *, timeout_seconds: int = 10) -> bool:
        """Receive and process one message, completing or abandoning it accordingly."""
        with self._client() as client:
            with client.get_queue_receiver(queue_name=self._queue_name, max_wait_time=timeout_seconds) as receiver:
                msgs = receiver.receive_messages(max_message_count=1, max_wait_time=timeout_seconds)
                if not msgs:
                    return False

                sb_msg = msgs[0]
                raw = _decode_sb_message(sb_msg)
                try:
                    message = IngestDocumentMessage.from_json(raw)
                except Exception as exc:  # noqa: BLE001
                    logger.exception("servicebus_message_decode_failed")
                    # Dead-letter malformed messages to avoid infinite retries
                    receiver.dead_letter_message(sb_msg, reason="decode_failed", error_description=str(exc))
                    return True

                try:
                    handler(message)
                    receiver.complete_message(sb_msg)
                    return True
                except Exception as exc:  # noqa: BLE001
                    # Abandon so it can be retried; DLQ thresholds are configured separately.
                    logger.exception("servicebus_handler_failed", extra={"doc_id": message.doc_id})
                    receiver.abandon_message(sb_msg)
                    return True


def _decode_sb_message(sb_msg: object) -> str:
    """Decode ServiceBusReceivedMessage body to string.

    SDK exposes body as an iterable of byte segments.
    """
    body = getattr(sb_msg, "body", None)
    if body is None:
        return ""
    try:
        # Typical case: iterable of bytes
        data = b"".join(bytes(b) for b in body)  # type: ignore[arg-type]
        return data.decode("utf-8", errors="replace")
    except Exception:
        # Fallback: try str()
        return str(body)

