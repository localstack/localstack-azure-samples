"""Blob Storage client for guestbook entries.

Stores all guestbook entries as a single JSON blob in Azure Blob Storage.
Writes use optimistic concurrency (ETag conditions), so concurrent replicas
of the container app cannot lose each other's updates.
"""

import json
import logging
import os
import random
import time
import uuid
from datetime import datetime

from azure.core import MatchConditions
from azure.core.exceptions import (
    ResourceExistsError,
    ResourceModifiedError,
    ResourceNotFoundError,
)
from azure.storage.blob import BlobServiceClient

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

ENTRIES_BLOB_NAME = "entries.json"

# Attempts per read-modify-write before giving up; each retry re-reads the
# blob, so a retry is only consumed when another writer got in between. The
# jittered backoff below desynchronizes concurrent losers, so the bound is
# about tolerating a burst of simultaneous writers, not elapsed time.
MAX_WRITE_ATTEMPTS = 10


def _backoff(attempt: int) -> None:
    """Sleep briefly with jitter so concurrent writers stop colliding."""
    time.sleep(random.uniform(0.05, 0.15) * (attempt + 1))


class BlobGuestbookClient:
    """CRUD operations for guestbook entries using Azure Blob Storage.

    All entries are stored in a single JSON blob:
        entries.json
    """

    def __init__(self, connection_string: str, container_name: str):
        self.blob_service = BlobServiceClient.from_connection_string(connection_string)
        self.container_client = self.blob_service.get_container_client(container_name)

    @classmethod
    def from_env(cls) -> "BlobGuestbookClient | None":
        """Create from environment variables.

        Required env vars:
            AZURE_STORAGE_CONNECTION_STRING - Blob Storage connection string
            BLOB_CONTAINER_NAME - Name of the blob container
        """
        connection_string = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
        container_name = os.environ.get("BLOB_CONTAINER_NAME")

        if not connection_string or not container_name:
            logger.warning(
                "AZURE_STORAGE_CONNECTION_STRING or BLOB_CONTAINER_NAME not set. "
                "Blob storage client not initialized."
            )
            return None

        logger.info("Initializing Blob Storage client for container: %s", container_name)
        return cls(connection_string, container_name)

    def _read_blob(self) -> tuple[list[dict[str, str]], str | None]:
        """Download and parse the JSON blob, together with its ETag.

        Returns ([], None) only when the blob doesn't exist yet. Any other
        read error propagates: treating a failed read as "no entries" would
        let the next write overwrite existing entries with a truncated list.
        """
        blob_client = self.container_client.get_blob_client(ENTRIES_BLOB_NAME)
        try:
            downloader = blob_client.download_blob()
        except ResourceNotFoundError:
            logger.info("No guestbook blob found yet")
            return [], None
        entries = json.loads(downloader.readall())
        logger.info("Read %d guestbook entries", len(entries))
        return entries, downloader.properties.etag

    def _try_write_blob(self, entries: list[dict[str, str]], etag: str | None) -> bool:
        """Upload the entries list, conditional on the ETag the read observed.

        Returns False when another writer changed (or created) the blob in the
        meantime, so the caller can re-read and retry.
        """
        blob_client = self.container_client.get_blob_client(ENTRIES_BLOB_NAME)
        data = json.dumps(entries, indent=2)
        try:
            if etag is None:
                blob_client.upload_blob(data, overwrite=False)
            else:
                blob_client.upload_blob(
                    data,
                    overwrite=True,
                    etag=etag,
                    match_condition=MatchConditions.IfNotModified,
                )
        except (ResourceExistsError, ResourceModifiedError):
            return False
        logger.info("Wrote %d guestbook entries", len(entries))
        return True

    def read_entries(self) -> list[dict[str, str]]:
        """Read all guestbook entries, newest first."""
        entries, _ = self._read_blob()
        return sorted(entries, key=lambda e: e.get("timestamp", ""), reverse=True)

    def insert_entry(self, author: str, message: str) -> dict[str, str]:
        """Insert a new guestbook entry.

        Returns:
            The inserted entry with generated 'id' and 'timestamp'
        """
        if not author or not author.strip():
            raise ValueError("Author cannot be None or empty")
        if not message or not message.strip():
            raise ValueError("Message cannot be None or empty")

        entry = {
            "id": str(uuid.uuid4()),
            "author": author.strip(),
            "message": message.strip(),
            "timestamp": datetime.now().isoformat(),
        }

        for attempt in range(MAX_WRITE_ATTEMPTS):
            entries, etag = self._read_blob()
            if self._try_write_blob([*entries, entry], etag):
                logger.info("Inserted guestbook entry %s", entry["id"])
                return entry
            logger.info("Concurrent write detected, retrying insert")
            _backoff(attempt)

        raise RuntimeError(f"Could not insert entry after {MAX_WRITE_ATTEMPTS} attempts")

    def delete_entry_by_id(self, entry_id: str) -> int:
        """Delete an entry by its ID.

        Returns:
            Number of entries deleted (0 or 1)
        """
        if not entry_id:
            raise ValueError("Entry ID cannot be None or empty")

        for attempt in range(MAX_WRITE_ATTEMPTS):
            entries, etag = self._read_blob()
            new_entries = [e for e in entries if e.get("id") != entry_id]
            deleted_count = len(entries) - len(new_entries)

            if deleted_count == 0:
                return 0
            if self._try_write_blob(new_entries, etag):
                logger.info("Deleted guestbook entry %s", entry_id)
                return deleted_count
            logger.info("Concurrent write detected, retrying delete")
            _backoff(attempt)

        raise RuntimeError(f"Could not delete entry after {MAX_WRITE_ATTEMPTS} attempts")
