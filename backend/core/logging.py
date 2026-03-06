from __future__ import annotations

import logging
import sys
from typing import Any, Dict

from core.request_context import correlation_id_ctx, request_id_ctx, user_id_ctx


class RequestContextFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        # Preserve explicit extras if already set by caller.
        if not hasattr(record, "request_id"):
            record.request_id = request_id_ctx.get()
        if not hasattr(record, "correlation_id"):
            record.correlation_id = correlation_id_ctx.get()
        if not hasattr(record, "user_id"):
            record.user_id = user_id_ctx.get()
        return True


class JsonFormatter(logging.Formatter):
    """A minimal JSON-ish log formatter without external dependencies.

    Container Apps + App Insights handle ingestion; we keep logs structured enough.
    """

    def format(self, record: logging.LogRecord) -> str:
        payload: Dict[str, Any] = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "time": self.formatTime(record, datefmt="%Y-%m-%dT%H:%M:%S%z"),
        }
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        # Include common extra fields when passed via logger.*(extra={...})
        for key in ("request_id", "correlation_id", "user_id", "conversation_id", "job_id", "doc_id"):
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        # Serialize manually to avoid hard dependency; keep it simple and safe
        try:
            import orjson  # type: ignore

            return orjson.dumps(payload).decode("utf-8")
        except Exception:
            return str(payload)


def setup_logging(level: str = "INFO") -> None:
    root = logging.getLogger()
    root.setLevel(level)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    handler.addFilter(RequestContextFilter())
    root.handlers.clear()
    root.addHandler(handler)

    # Quiet noisy libs in dev
    logging.getLogger("httpx").setLevel("WARNING")
    logging.getLogger("uvicorn.access").setLevel("INFO")
