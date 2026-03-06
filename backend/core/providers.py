from __future__ import annotations

import logging

from core.azure_search_store import AzureSearchStore
from core.blob_store import AzureBlobStore, BlobStore, LocalBlobStore
from core.config import settings
from core.cosmos_store import CosmosStore
from core.db import SqliteStore
from core.qdrant_store import QdrantStore
from core.queue_provider import QueueProvider
from core.redis_queue import RedisQueue
from core.servicebus_queue import ServiceBusQueue
from core.store import StateStore
from core.vector_store import VectorStore

logger = logging.getLogger(__name__)


def build_state_store() -> StateStore:
    provider = settings.state_provider.lower().strip()
    if provider in ("sqlite", "local"):
        return SqliteStore(settings.sqlite_path)
    if provider == "cosmos":
        return CosmosStore(
            endpoint=settings.azure_cosmos_endpoint,
            key=settings.azure_cosmos_key,
            database_name=settings.azure_cosmos_db,
            conversations_container=settings.azure_cosmos_container_conversations,
            ingest_jobs_container=settings.azure_cosmos_container_ingest_jobs,
            agent_logs_container=settings.azure_cosmos_container_agent_logs,
        )
    raise ValueError(f"Unknown EKIP_STATE_PROVIDER: {settings.state_provider}")


def build_queue() -> QueueProvider:
    provider = settings.queue_provider.lower().strip()
    if provider == "redis":
        return RedisQueue(settings.redis_url, settings.redis_ingest_queue)
    if provider in ("servicebus", "sb"):
        return ServiceBusQueue(
            connection_string=settings.azure_servicebus_connection_string,
            fully_qualified_namespace=settings.azure_servicebus_fqdn,
            queue_name=settings.azure_servicebus_queue,
        )
    raise ValueError(f"Unknown EKIP_QUEUE_PROVIDER: {settings.queue_provider}")


def build_blob_store() -> BlobStore:
    provider = settings.storage_provider.lower().strip()
    if provider in ("local", "disk"):
        return LocalBlobStore(settings.uploads_dir)
    if provider in ("azureblob", "blob", "azure"):
        return AzureBlobStore(
            connection_string=settings.azure_storage_connection_string,
            account_url=settings.azure_storage_account_url,
            container_name=settings.azure_storage_container_raw,
        )
    raise ValueError(f"Unknown EKIP_STORAGE_PROVIDER: {settings.storage_provider}")


def build_vector_store() -> VectorStore:
    """Create vector store adapter without forcing connectivity at app startup.

    We call store.ensure() lazily on first ingest/search so containers can start in any order.
    """
    provider = settings.index_provider.lower().strip()
    if provider == "qdrant":
        return QdrantStore(url=str(settings.qdrant_url), collection=settings.qdrant_collection)
    if provider in ("azuresearch", "search", "ai-search"):
        return AzureSearchStore(
            endpoint=settings.azure_search_endpoint,
            admin_key=settings.azure_search_admin_key,
            index_name=settings.azure_search_index_name,
            vector_dim=settings.azure_search_vector_dim,
        )
    raise ValueError(f"Unknown EKIP_INDEX_PROVIDER: {settings.index_provider}")
