from __future__ import annotations


class EKIPError(Exception):
    """Base application error."""


class ConfigurationError(EKIPError):
    """Raised when required configuration is missing."""


class IngestionError(EKIPError):
    """Raised when document ingestion fails."""


class RetrievalError(EKIPError):
    """Raised when retrieval fails."""


class LLMError(EKIPError):
    """Raised when LLM call fails."""


class NotFoundError(EKIPError):
    """Raised when an entity is not found."""


class RateLimitError(EKIPError):
    """Raised when upstream rate limits are hit."""


def require(value: str, name: str) -> str:
    if not value or not value.strip():
        raise ConfigurationError(f"Missing required setting: {name}")
    return value
