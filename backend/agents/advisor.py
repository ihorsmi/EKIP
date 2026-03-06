from __future__ import annotations

import logging
from typing import List

from openai import AzureOpenAI
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from core.config import settings
from core.exceptions import ConfigurationError, LLMError, require
from core.vector_store import RetrievedChunk

logger = logging.getLogger(__name__)


def _client() -> AzureOpenAI:
    endpoint = require(settings.azure_openai_endpoint, "AZURE_OPENAI_ENDPOINT")
    key = require(settings.azure_openai_api_key, "AZURE_OPENAI_API_KEY")
    return AzureOpenAI(azure_endpoint=endpoint, api_key=key, api_version=settings.azure_openai_api_version)


def _format_context(chunks: List[RetrievedChunk]) -> str:
    return "\n".join([f"- ({c.filename}#{c.chunk_index}) {c.text[:220]}" for c in chunks])


@retry(
    reraise=True,
    stop=stop_after_attempt(4),
    wait=wait_exponential(multiplier=0.8, min=1, max=8),
    retry=retry_if_exception_type(Exception),
)
def advise(question: str, answer: str, chunks: List[RetrievedChunk]) -> List[str]:
    """Agent 4 - Advisor: produce action recommendations and decision notes."""
    try:
        client = _client()
        system = (
            "You are EKIP Advisor. Produce 3-6 concrete, enterprise-friendly action items "
            "based on the answer and context. Each item should start with a verb."
        )
        user = (
            f"QUESTION:\n{question}\n\nANSWER:\n{answer}\n\n"
            f"CONTEXT SNIPPETS:\n{_format_context(chunks)}\n\n"
            "Return ONLY a JSON array of strings."
        )
        resp = client.chat.completions.create(
            model=settings.azure_openai_chat_deployment,
            messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
            temperature=0.1,
        )
        raw = (resp.choices[0].message.content or "").strip()
        import json

        parsed = json.loads(raw)
        if not isinstance(parsed, list) or not all(isinstance(x, str) for x in parsed):
            raise LLMError("Advisor returned invalid JSON list.")
        return [x.strip() for x in parsed if x.strip()][:10]
    except ConfigurationError:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("advice_failed")
        raise LLMError(f"Advisor failed: {exc}") from exc

