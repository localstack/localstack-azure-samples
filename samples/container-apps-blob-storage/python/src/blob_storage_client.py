"""Blob Storage client for guestbook entries.

Stores all guestbook entries as a single JSON blob in Azure Blob Storage.
"""

import json
import logging
import os
import uuid
from datetime import datetime

from azure.core.exceptions import ResourceNotFoundError
from azure.storage.blob import BlobServiceClient

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

ENTRIES_BLOB_NAME = "entries.json"


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

    def _read_blob(self) -> list[dict[str, str]]:
        """Download and parse the JSON blob. Returns [] if the blob doesn't exist."""
        try:
            blob_client = self.container_client.get_blob_client(ENTRIES_BLOB_NAME)
            data = blob_client.download_blob().readall()
            entries = json.loads(data)
            logger.info("Read %d guestbook entries", len(entries))
            return entries
        except ResourceNotFoundError:
            logger.info("No guestbook blob found yet")
            return []
        except Exception as e:
            logger.error("Error reading guestbook entries: %s", e)
            return []

    def _write_blob(self, entries: list[dict[str, str]]):
        """Upload the entries list as a JSON blob (overwrite)."""
        try:
            blob_client = self.container_client.get_blob_client(ENTRIES_BLOB_NAME)
            data = json.dumps(entries, indent=2)
            blob_client.upload_blob(data, overwrite=True)
            logger.info("Wrote %d guestbook entries", len(entries))
        except Exception as e:
            logger.error("Error writing guestbook entries: %s", e)
            raise

    def read_entries(self) -> list[dict[str, str]]:
        """Read all guestbook entries, newest first."""
        entries = self._read_blob()
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

        entries = self._read_blob()
        entry = {
            "id": str(uuid.uuid4()),
            "author": author.strip(),
            "message": message.strip(),
            "timestamp": datetime.now().isoformat(),
        }
        entries.append(entry)

        self._write_blob(entries)
        logger.info("Inserted guestbook entry %s", entry["id"])
        return entry

    def delete_entry_by_id(self, entry_id: str) -> int:
        """Delete an entry by its ID.

        Returns:
            Number of entries deleted (0 or 1)
        """
        if not entry_id:
            raise ValueError("Entry ID cannot be None or empty")

        entries = self._read_blob()
        new_entries = [e for e in entries if e.get("id") != entry_id]
        deleted_count = len(entries) - len(new_entries)

        if deleted_count > 0:
            self._write_blob(new_entries)
            logger.info("Deleted guestbook entry %s", entry_id)

        return deleted_count
