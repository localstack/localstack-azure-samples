"""Blob Storage client for vacation activities.

Stores activities as a JSON blob per user in Azure Blob Storage.
Replaces the SQL/CosmosDB backends used in other vacation planner samples.
"""

import json
import logging
import os
import uuid
from datetime import datetime
from typing import Optional

from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import ResourceNotFoundError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


class BlobActivitiesClient:
    """CRUD operations for vacation activities using Azure Blob Storage.

    Each user's activities are stored as a single JSON blob:
        {username}/activities.json
    """

    def __init__(self, connection_string: str, container_name: str):
        self.blob_service = BlobServiceClient.from_connection_string(connection_string)
        self.container_client = self.blob_service.get_container_client(container_name)

    @classmethod
    def from_env(cls) -> Optional["BlobActivitiesClient"]:
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

    def _blob_name(self, username: str) -> str:
        return f"{username}/activities.json"

    def _read_blob(self, username: str) -> list[dict]:
        """Download and parse the JSON blob. Returns [] if blob doesn't exist."""
        blob_name = self._blob_name(username)
        try:
            blob_client = self.container_client.get_blob_client(blob_name)
            data = blob_client.download_blob().readall()
            activities = json.loads(data)
            logger.info("Read %d activities for user: %s", len(activities), username)
            return activities
        except ResourceNotFoundError:
            logger.info("No activities blob found for user: %s", username)
            return []
        except Exception as e:
            logger.error("Error reading activities for user %s: %s", username, e)
            return []

    def _write_blob(self, username: str, activities: list[dict]):
        """Upload the activities list as JSON blob (overwrite)."""
        blob_name = self._blob_name(username)
        try:
            blob_client = self.container_client.get_blob_client(blob_name)
            data = json.dumps(activities, indent=2)
            blob_client.upload_blob(data, overwrite=True)
            logger.info("Wrote %d activities for user: %s", len(activities), username)
        except Exception as e:
            logger.error("Error writing activities for user %s: %s", username, e)
            raise

    def read_activities(self, username: str) -> list[dict]:
        """Read all activities for a given username."""
        return self._read_blob(username)

    def insert_activity(self, row: dict) -> Optional[dict]:
        """Insert a new activity.

        Args:
            row: dict with 'username' and 'activity' keys

        Returns:
            The inserted activity with generated 'id' and 'timestamp'
        """
        if not row or not row.get("activity"):
            raise ValueError("Activity cannot be None or empty")

        username = row.get("username")
        if not username:
            raise ValueError("Username cannot be None or empty")

        activities = self._read_blob(username)

        row["id"] = str(uuid.uuid4())
        row["timestamp"] = datetime.now().isoformat()
        activities.append(row)

        self._write_blob(username, activities)
        logger.info("Inserted activity %s for user: %s", row["id"], username)
        return row

    def delete_activity_by_id(self, activity_id: str, username: str = None) -> int:
        """Delete an activity by its ID.

        Returns:
            Number of activities deleted (0 or 1)
        """
        if not activity_id:
            raise ValueError("Activity ID cannot be None or empty")

        if not username:
            raise ValueError("Username is required for blob storage operations")

        activities = self._read_blob(username)
        new_activities = [a for a in activities if a.get("id") != activity_id]
        deleted_count = len(activities) - len(new_activities)

        if deleted_count > 0:
            self._write_blob(username, new_activities)
            logger.info("Deleted activity %s for user: %s", activity_id, username)

        return deleted_count

    def update_activity_by_id(
        self, activity_id: str, new_activity: str, username: str = None
    ) -> Optional[dict]:
        """Update an activity's text by its ID.

        Returns:
            The updated activity dict, or None if not found
        """
        if not activity_id:
            raise ValueError("Activity ID cannot be None or empty")
        if not new_activity:
            raise ValueError("New activity text cannot be None or empty")
        if not username:
            raise ValueError("Username is required for blob storage operations")

        activities = self._read_blob(username)
        for activity in activities:
            if activity.get("id") == activity_id:
                activity["activity"] = new_activity
                activity["timestamp"] = datetime.now().isoformat()
                self._write_blob(username, activities)
                logger.info("Updated activity %s for user: %s", activity_id, username)
                return activity

        logger.warning("Activity %s not found for user: %s", activity_id, username)
        return None
