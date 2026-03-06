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
    lines: List[str] = []
    for i, c in enumerate(chunks, start=1):
        lines.append(f"[{i}] doc_id={c.doc_id} file={c.filename} chunk={c.chunk_index}\n{c.text}")
    return "\n\n".join(lines)


@retry(
    reraise=True,
    stop=stop_after_attempt(4),
    wait=wait_exponential(multiplier=0.8, min=1, max=8),
    retry=retry_if_exception_type(Exception),
)
def summarize(question: str, chunks: List[RetrievedChunk]) -> str:
    """Agent 3 - Summarizer: produce an answer grounded in retrieved context."""
    try:
        client = _client()
        system = (
            "You are EKIP Summarizer. Answer the user using ONLY the provided context. "
            "If the context is insufficient, say what is missing and ask a specific follow-up question. "
            "Be concise, factual, and avoid speculation."
        )
        user = (
            f"QUESTION:\n{question}\n\n"
            f"CONTEXT (cite with [1], [2]... where relevant):\n{_format_context(chunks)}"
        )
        resp = client.chat.completions.create(
            model=settings.azure_openai_chat_deployment,
            messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
            temperature=0.2,
        )
        content = resp.choices[0].message.content or ""
        return content.strip()
    except ConfigurationError:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("summarization_failed")
        raise LLMError(f"Summarization failed: {exc}") from exc

