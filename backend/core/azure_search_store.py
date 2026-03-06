from __future__ import annotations

import logging
import re
from typing import Any, Dict, List, Sequence

from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    HnswParameters,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SearchableField,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)
from azure.search.documents.models import VectorizedQuery

from core.vector_store import RetrievedChunk, VectorStore

logger = logging.getLogger(__name__)


class AzureSearchStore(VectorStore):
    """Azure AI Search vector+keyword store.

    This store supports:
      - Upserting chunks with embeddings into an AI Search index
      - Hybrid search (keyword + vector) for retrieval

    Auth options:
      - Admin key (local dev): AZURE_SEARCH_ADMIN_KEY
      - Managed identity (Azure): omit key and use DefaultAzureCredential
    """

    def __init__(
        self,
        *,
        endpoint: str,
        admin_key: str,
        index_name: str,
        vector_dim: int,
    ) -> None:
        self.endpoint = endpoint.rstrip("/")
        self.admin_key = admin_key.strip()
        self.index_name = index_name
        self.vector_dim = int(vector_dim)

        if not self.endpoint:
            raise ValueError("AZURE_SEARCH_ENDPOINT is required for azuresearch provider")
        if not self.index_name:
            raise ValueError("AZURE_SEARCH_INDEX_NAME is required for azuresearch provider")

        if self.admin_key:
            self._credential = AzureKeyCredential(self.admin_key)
        else:
            self._credential = DefaultAzureCredential()

        self._index_client = SearchIndexClient(endpoint=self.endpoint, credential=self._credential)
        self._search_client = SearchClient(endpoint=self.endpoint, index_name=self.index_name, credential=self._credential)

    def ensure(self) -> None:
        # Create the index if missing. If it exists, we do nothing.
        try:
            self._index_client.get_index(self.index_name)
            return
        except Exception:
            pass

        index = _build_index(self.index_name, vector_dim=self.vector_dim)
        self._index_client.create_index(index)
        logger.info("search_index_created", extra={"index": self.index_name})

    def upsert_chunks(self, *, embeddings: Sequence[Sequence[float]], payloads: Sequence[Dict[str, Any]]) -> int:
        if len(embeddings) != len(payloads):
            raise ValueError("Embeddings and payloads length mismatch")

        docs: List[Dict[str, Any]] = []
        for i, (emb, payload) in enumerate(zip(embeddings, payloads)):
            doc_id = str(payload.get("doc_id", ""))
            chunk_index = int(payload.get("chunk_index", i))
            # Azure AI Search document keys may only include [A-Za-z0-9_-=].
            # Normalize any unsupported characters (e.g., UUID dashes are fine, but ":" is not).
            safe_doc_id = re.sub(r"[^A-Za-z0-9_\-=]", "-", doc_id)
            key = f"{safe_doc_id}-{chunk_index}"
            docs.append(
                {
                    "id": key,
                    "doc_id": doc_id,
                    "filename": str(payload.get("filename", "")),
                    "chunk_index": chunk_index,
                    "text": str(payload.get("text", "")),
                    "contentVector": list(emb),
                }
            )

        result = self._search_client.upload_documents(documents=docs)
        # result is a list of IndexingResult; count successes
        ok = sum(1 for r in result if getattr(r, "succeeded", False))
        if ok != len(docs):
            failed = [getattr(r, "key", "?") for r in result if not getattr(r, "succeeded", False)]
            logger.warning("search_upsert_partial_failure", extra={"failed": failed[:10], "failed_count": len(failed)})
        return ok

    def search(self, query_embedding: Sequence[float], *, limit: int = 6, query_text: str | None = None) -> List[RetrievedChunk]:
        # Hybrid search: provide both keyword query and vector query.
        # If query_text is omitted, we still pass a wildcard to avoid empty searches.
        q = query_text or "*"
        vq = VectorizedQuery(vector=list(query_embedding), k_nearest_neighbors=limit, fields="contentVector")

        results = self._search_client.search(
            search_text=q,
            vector_queries=[vq],
            top=limit,
            select=["doc_id", "filename", "chunk_index", "text"],
        )

        out: List[RetrievedChunk] = []
        for r in results:
            # r is SearchDocument dict-like
            out.append(
                RetrievedChunk(
                    doc_id=str(r.get("doc_id", "")),
                    filename=str(r.get("filename", "")),
                    chunk_index=int(r.get("chunk_index", 0)),
                    score=float(r.get("@search.score", 0.0) or 0.0),
                    text=str(r.get("text", "")),
                )
            )
        return out


def _build_index(index_name: str, *, vector_dim: int) -> SearchIndex:
    # Vector config: HNSW with cosine distance.
    hnsw = HnswAlgorithmConfiguration(
        name="hnsw-config",
        parameters=HnswParameters(metric="cosine", m=4, ef_construction=400, ef_search=500),
    )
    vector_search = VectorSearch(
        algorithms=[hnsw],
        profiles=[VectorSearchProfile(name="vector-profile", algorithm_configuration_name="hnsw-config")],
    )

    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True, filterable=True, sortable=False, facetable=False),
        SimpleField(name="doc_id", type=SearchFieldDataType.String, filterable=True, sortable=False, facetable=False),
        SimpleField(name="filename", type=SearchFieldDataType.String, filterable=True, sortable=False, facetable=False),
        SimpleField(name="chunk_index", type=SearchFieldDataType.Int32, filterable=True, sortable=True, facetable=False),
        SearchableField(name="text", type=SearchFieldDataType.String, analyzer_name="en.lucene"),
        # Vector field: store=False + hidden=True to avoid returning large vectors in results.
        SearchField(
            name="contentVector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=vector_dim,
            vector_search_profile_name="vector-profile",
            stored=False,
            hidden=True,
        ),
    ]

    return SearchIndex(name=index_name, fields=fields, vector_search=vector_search)
