from __future__ import annotations

import logging
import uuid
from typing import Any, Dict, List, Sequence

from qdrant_client import QdrantClient
from qdrant_client.http import models as qmodels

from core.vector_store import RetrievedChunk, VectorStore

logger = logging.getLogger(__name__)

# text-embedding-3-large outputs 3072 dims in Azure OpenAI
DEFAULT_VECTOR_SIZE = 3072


class QdrantStore(VectorStore):
    def __init__(self, url: str, collection: str, vector_size: int = DEFAULT_VECTOR_SIZE) -> None:
        self.client = QdrantClient(url=url)
        self.collection = collection
        self.vector_size = vector_size

    def ensure(self) -> None:
        existing = self.client.get_collections().collections
        if any(c.name == self.collection for c in existing):
            return
        self.client.create_collection(
            collection_name=self.collection,
            vectors_config=qmodels.VectorParams(size=self.vector_size, distance=qmodels.Distance.COSINE),
        )
        logger.info("qdrant_collection_created", extra={"collection": self.collection})

    def upsert_chunks(
        self,
        *,
        embeddings: Sequence[Sequence[float]],
        payloads: Sequence[Dict[str, Any]],
    ) -> int:
        if len(embeddings) != len(payloads):
            raise ValueError("Embeddings and payloads length mismatch")

        points: List[qmodels.PointStruct] = []
        for emb, payload in zip(embeddings, payloads):
            points.append(qmodels.PointStruct(id=str(uuid.uuid4()), vector=list(emb), payload=payload))

        self.client.upsert(collection_name=self.collection, points=points)
        return len(points)

    def search(self, query_embedding: Sequence[float], *, limit: int = 6) -> List[RetrievedChunk]:
        hits = self.client.search(
            collection_name=self.collection,
            query_vector=list(query_embedding),
            limit=limit,
            with_payload=True,
        )
        out: List[RetrievedChunk] = []
        for h in hits:
            p = h.payload or {}
            out.append(
                RetrievedChunk(
                    doc_id=str(p.get("doc_id", "")),
                    filename=str(p.get("filename", "")),
                    chunk_index=int(p.get("chunk_index", 0)),
                    score=float(h.score or 0.0),
                    text=str(p.get("text", "")),
                )
            )
        return out
