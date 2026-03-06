from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Dict, List, Sequence


@dataclass(frozen=True)
class RetrievedChunk:
    doc_id: str
    filename: str
    chunk_index: int
    score: float
    text: str


class VectorStore(ABC):
    @abstractmethod
    def ensure(self) -> None:
        raise NotImplementedError

    @abstractmethod
    def upsert_chunks(self, *, embeddings: Sequence[Sequence[float]], payloads: Sequence[Dict[str, Any]]) -> int:
        raise NotImplementedError

    @abstractmethod
    def search(self, query_embedding: Sequence[float], *, limit: int = 6) -> List[RetrievedChunk]:
        raise NotImplementedError
