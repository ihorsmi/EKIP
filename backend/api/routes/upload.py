from __future__ import annotations

import json
import logging
import re
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from starlette.concurrency import run_in_threadpool

from api.auth import AuthContext, require_role
from api.deps import get_queue, get_store, get_blob_store
from core.blob_store import BlobStore
from core.queue_messages import IngestDocumentMessage, utcnow_iso
from core.queue_provider import QueueProvider
from core.schemas import IngestJob, UploadResponse
from core.store import StateStore

logger = logging.getLogger(__name__)
router = APIRouter()


def _safe_name(name: str) -> str:
    # Keep it blob-safe and filesystem-safe (no slashes, no weird chars)
    name = name.strip().replace("\\", "_").replace("/", "_")
    name = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
    return name or "upload.bin"


@router.post("/upload", response_model=UploadResponse)
async def upload_document(
    file: UploadFile = File(...),
    store: StateStore = Depends(get_store),
    queue: QueueProvider = Depends(get_queue),
    blob_store: BlobStore = Depends(get_blob_store),
    auth: AuthContext = Depends(require_role("Admin", "Analyst")),
) -> UploadResponse:
    if not file.filename:
        raise HTTPException(status_code=400, detail="Missing filename")

    filename = _safe_name(file.filename)
    content_type = file.content_type or "application/octet-stream"
    uploaded_by = auth.user_id

    # 1) Create ingest job (job_id becomes doc_id across the system)
    metadata = {"filename": filename, "content_type": content_type, "uploaded_by": uploaded_by}
    job_id = store.create_ingest_job(filename, metadata_json=json.dumps(metadata))

    # 2) Persist raw file -> BlobStore (local disk or Azure Blob)
    # Stream to a temp file first to avoid reading into memory.
    suffix = Path(filename).suffix
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp_path = Path(tmp.name)

    try:
        # Copy upload stream -> tmp file in a threadpool (UploadFile.file is sync)
        def _copy() -> None:
            file.file.seek(0)
            import shutil
            with tmp_path.open("wb") as out:
                shutil.copyfileobj(file.file, out, length=1024 * 1024)

        await run_in_threadpool(_copy)

        dest_name = f"{job_id}_{filename}"
        stored = await run_in_threadpool(blob_store.save, src_file=tmp_path, dest_name=dest_name, content_type=content_type)

        # Update job metadata with blob_url so worker can fetch it regardless of provider
        metadata.update({"blob_url": stored.blob_url, "stored_as": stored.stored_as, "size_bytes": stored.size_bytes})
        store.update_ingest_job(job_id, "queued", metadata_json=json.dumps(metadata))

        # 3) Enqueue ingestion message (Redis or Service Bus)
        msg = IngestDocumentMessage(
            doc_id=job_id,
            blob_url=stored.blob_url,
            filename=filename,
            content_type=content_type,
            uploaded_by=uploaded_by,
            uploaded_at=utcnow_iso(),
            metadata={"size_bytes": stored.size_bytes},
        )
        await run_in_threadpool(queue.enqueue, msg)

        logger.info("upload_received", extra={"job_id": job_id, "blob_url": stored.blob_url})
        return UploadResponse(job_id=job_id, filename=filename, status="queued")
    except Exception as exc:  # noqa: BLE001
        logger.exception("upload_failed", extra={"job_id": job_id})
        store.update_ingest_job(job_id, "failed", error=str(exc))
        raise HTTPException(status_code=500, detail="Upload failed") from exc
    finally:
        try:
            tmp_path.unlink(missing_ok=True)
        except Exception:
            pass


@router.get("/upload/{job_id}", response_model=IngestJob)
def get_upload_job(
    job_id: str,
    store: StateStore = Depends(get_store),
    _auth: AuthContext = Depends(require_role("Admin", "Analyst", "Viewer")),
) -> IngestJob:
    row = store.get_ingest_job(job_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Job not found")
    try:
        metadata = json.loads(row.metadata_json or "{}")
    except Exception:
        metadata = {}
    return IngestJob(
        job_id=row.job_id,
        filename=row.filename,
        status=row.status,
        error=row.error,
        chunks_indexed=row.chunks_indexed,
        created_at=row.created_at,
        updated_at=row.updated_at,
        metadata=metadata if isinstance(metadata, dict) else {},
    )


@router.get("/upload", response_model=list[IngestJob])
def list_upload_jobs(
    limit: int = 20,
    store: StateStore = Depends(get_store),
    _auth: AuthContext = Depends(require_role("Admin", "Analyst", "Viewer")),
) -> list[IngestJob]:
    rows = store.list_ingest_jobs(limit=max(1, min(limit, 200)))
    out: list[IngestJob] = []
    for row in rows:
        try:
            metadata = json.loads(row.metadata_json or "{}")
        except Exception:
            metadata = {}
        out.append(
            IngestJob(
                job_id=row.job_id,
                filename=row.filename,
                status=row.status,
                error=row.error,
                chunks_indexed=row.chunks_indexed,
                created_at=row.created_at,
                updated_at=row.updated_at,
                metadata=metadata if isinstance(metadata, dict) else {},
            )
        )
    return out
