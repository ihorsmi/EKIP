from __future__ import annotations

import json
import logging
import tempfile
import time
from pathlib import Path

from agents.ingestor import IngestorAgent
from core.blob_store import BlobStore
from core.config import settings
from core.logging import setup_logging
from core.providers import build_blob_store, build_queue, build_state_store, build_vector_store
from core.queue_messages import IngestDocumentMessage
from core.queue_provider import QueueProvider
from core.store import StateStore

setup_logging(settings.log_level)
logger = logging.getLogger(__name__)


def main() -> None:
    settings.ensure_dirs()

    store: StateStore = build_state_store()
    store.migrate()
    queue: QueueProvider = build_queue()
    blob_store: BlobStore = build_blob_store()
    vector_store = build_vector_store()

    ingestor = IngestorAgent(store=vector_store)

    def handle(msg: IngestDocumentMessage) -> None:
        logger.info("worker_received", extra={"doc_id": msg.doc_id, "blob_url": msg.blob_url})
        store.update_ingest_job(msg.doc_id, "processing")
        try:
            with tempfile.TemporaryDirectory() as td:
                local_path = blob_store.download_to_path(blob_url=msg.blob_url, dest_dir=Path(td))
                doc_id, chunks = ingestor.ingest(file_path=str(local_path), filename=msg.filename, doc_id=msg.doc_id)

            # Persist job result
            meta = {"blob_url": msg.blob_url, "filename": msg.filename, "content_type": msg.content_type}
            store.update_ingest_job(msg.doc_id, "completed", chunks_indexed=chunks, metadata_json=json.dumps(meta))
            logger.info("worker_completed", extra={"doc_id": doc_id, "chunks": chunks})
        except Exception as exc:  # noqa: BLE001
            # Mark job as failed so API callers don't see permanent "processing" when retries exhaust.
            store.update_ingest_job(msg.doc_id, "failed", error=str(exc))
            logger.exception("worker_failed", extra={"doc_id": msg.doc_id})
            raise

    logger.info(
        "worker_started",
        extra={
            "queue_provider": settings.queue_provider,
            "storage_provider": settings.storage_provider,
            "index_provider": settings.index_provider,
        },
    )

    while True:
        try:
            processed = queue.process_one(handle, timeout_seconds=10)
            if not processed:
                time.sleep(0.25)
        except KeyboardInterrupt:
            logger.info("worker_stopping")
            break
        except Exception:  # noqa: BLE001
            logger.exception("worker_loop_error")
            time.sleep(1.0)


if __name__ == "__main__":
    main()
