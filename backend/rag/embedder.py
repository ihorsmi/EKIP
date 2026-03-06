from __future__ import annotations

import logging
from typing import List, Sequence

from openai import AzureOpenAI
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from core.config import settings
from core.exceptions import ConfigurationError, LLMError, require

logger = logging.getLogger(__name__)


def _client() -> AzureOpenAI:
    endpoint = require(settings.azure_openai_endpoint, "AZURE_OPENAI_ENDPOINT")
    key = require(settings.azure_openai_api_key, "AZURE_OPENAI_API_KEY")
    return AzureOpenAI(azure_endpoint=endpoint, api_key=key, api_version=settings.azure_openai_api_version)


@retry(
    reraise=True,
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=0.8, min=1, max=10),
    retry=retry_if_exception_type(Exception),
)
def embed_texts(texts: Sequence[str]) -> List[List[float]]:
    """Create embeddings for a list of texts.

    Uses Azure OpenAI embedding deployment set via AZURE_OPENAI_EMBED_DEPLOYMENT.
    """
    if not texts:
        return []
    try:
        client = _client()
        resp = client.embeddings.create(model=settings.azure_openai_embed_deployment, input=list(texts))
        return [d.embedding for d in resp.data]
    except ConfigurationError:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("embedding_failed")
        raise LLMError(f"Embedding call failed: {exc}") from exc
