from __future__ import annotations

import logging
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from core.request_context import correlation_id_ctx, request_id_ctx, user_id_ctx

logger = logging.getLogger(__name__)


class CorrelationIdMiddleware(BaseHTTPMiddleware):
    """Injects request/correlation IDs and emits request completion logs."""

    async def dispatch(self, request: Request, call_next) -> Response:  # type: ignore[override]
        request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
        correlation_id = request.headers.get("X-Correlation-ID") or request_id

        token_req = request_id_ctx.set(request_id)
        token_corr = correlation_id_ctx.set(correlation_id)
        token_user = user_id_ctx.set("")
        request.state.request_id = request_id
        request.state.correlation_id = correlation_id

        started = time.perf_counter()
        try:
            response = await call_next(request)
        finally:
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            logger.info(
                "request_completed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": getattr(locals().get("response"), "status_code", 500),
                    "duration_ms": elapsed_ms,
                },
            )
            request_id_ctx.reset(token_req)
            correlation_id_ctx.reset(token_corr)
            user_id_ctx.reset(token_user)

        response.headers["X-Request-ID"] = request_id
        response.headers["X-Correlation-ID"] = correlation_id
        return response
