from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Callable

from core.queue_messages import IngestDocumentMessage

logger = logging.getLogger(__name__)


class QueueProvider(ABC):
    """Abstract queue provider.

    We use a **push + pull** interface for workers:

    - enqueue(message) is used by the API /upload.
    - process_one(handler) is used by the worker. The provider is responsible for ACK/NACK.

    This keeps Redis and Azure Service Bus behaviour consistent.
    """

    @abstractmethod
    def enqueue(self, message: IngestDocumentMessage) -> None:
        raise NotImplementedError

    @abstractmethod
    def process_one(self, handler: Callable[[IngestDocumentMessage], None], *, timeout_seconds: int = 10) -> bool:
        """Receive at most one message and run handler(message).

        Returns True if a message was received (and handled), False otherwise.
        """
        raise NotImplementedError
