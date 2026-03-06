from __future__ import annotations

import logging
import shutil
import tempfile
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse, unquote

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobClient, BlobServiceClient, ContentSettings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class StoredBlob:
    blob_url: str
    stored_as: str
    size_bytes: int


class BlobStore(ABC):
    """Raw document storage abstraction."""

    @abstractmethod
    def save(self, *, src_file: Path, dest_name: str, content_type: str) -> StoredBlob:
        raise NotImplementedError

    @abstractmethod
    def download_to_path(self, *, blob_url: str, dest_dir: Path) -> Path:
        raise NotImplementedError


class LocalBlobStore(BlobStore):
    def __init__(self, uploads_dir: Path) -> None:
        self.uploads_dir = uploads_dir
        self.uploads_dir.mkdir(parents=True, exist_ok=True)

    def save(self, *, src_file: Path, dest_name: str, content_type: str) -> StoredBlob:  # noqa: ARG002
        dest = self.uploads_dir / dest_name
        shutil.copyfile(src_file, dest)
        return StoredBlob(blob_url=dest.as_uri(), stored_as=dest.name, size_bytes=dest.stat().st_size)

    def download_to_path(self, *, blob_url: str, dest_dir: Path) -> Path:  # noqa: ARG002
        # file:// URI
        parsed = urlparse(blob_url)
        if parsed.scheme != "file":
            raise ValueError(f"LocalBlobStore expected file:// URL, got: {blob_url}")
        # Windows paths can come in as /C:/... ; Path handles it if we unquote and strip leading slash if needed
        path_str = unquote(parsed.path)
        if path_str.startswith("/") and len(path_str) > 3 and path_str[2] == ":":
            path_str = path_str.lstrip("/")
        return Path(path_str)


class AzureBlobStore(BlobStore):
    """Azure Blob Storage implementation.

    Auth options:
    - Connection string (local dev): AZURE_STORAGE_CONNECTION_STRING
    - Managed identity (Azure): AZURE_STORAGE_ACCOUNT_URL + DefaultAzureCredential
    """

    def __init__(self, *, connection_string: str, account_url: str, container_name: str) -> None:
        self._connection_string = connection_string.strip()
        self._account_url = account_url.strip()
        self._container = container_name.strip()

        if not self._container:
            raise ValueError("Blob container name is required")

        if not self._connection_string and not self._account_url:
            raise ValueError("Provide AZURE_STORAGE_CONNECTION_STRING or AZURE_STORAGE_ACCOUNT_URL")

        if self._connection_string:
            self._service_client = BlobServiceClient.from_connection_string(self._connection_string)
            self._credential = None
        else:
            cred = DefaultAzureCredential()
            self._service_client = BlobServiceClient(account_url=self._account_url, credential=cred)
            self._credential = cred

        # Ensure container exists (idempotent)
        try:
            self._service_client.create_container(self._container)
            logger.info("blob_container_created", extra={"container": self._container})
        except Exception:
            # Already exists or no permission; safe to ignore here.
            pass

    def save(self, *, src_file: Path, dest_name: str, content_type: str) -> StoredBlob:
        blob_client = self._service_client.get_blob_client(container=self._container, blob=dest_name)
        with src_file.open("rb") as f:
            blob_client.upload_blob(
                f,
                overwrite=True,
                content_settings=ContentSettings(content_type=content_type or "application/octet-stream"),
            )
        props = blob_client.get_blob_properties()
        return StoredBlob(blob_url=blob_client.url, stored_as=dest_name, size_bytes=int(props.size))

    def download_to_path(self, *, blob_url: str, dest_dir: Path) -> Path:
        dest_dir.mkdir(parents=True, exist_ok=True)
        filename = Path(urlparse(blob_url).path).name or "download.bin"
        dest = dest_dir / filename

        # With connection-string auth, create the client from the service client because
        # BlobClient.from_blob_url expects key/token/SAS credential, not a connection string.
        if self._connection_string:
            parsed = urlparse(blob_url)
            path = parsed.path.lstrip("/")
            container, _, blob_name = path.partition("/")
            if not container or not blob_name:
                raise ValueError(f"Invalid blob URL path: {blob_url}")
            bc = self._service_client.get_blob_client(container=container, blob=blob_name)
        else:
            bc = BlobClient.from_blob_url(blob_url, credential=self._credential)
        stream = bc.download_blob()
        data = stream.readall()
        dest.write_bytes(data)
        return dest
