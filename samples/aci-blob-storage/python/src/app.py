"""Flask application for managing vacation activities using Azure Blob Storage.

This is the ACI variant of the Vacation Planner sample app.
It uses Azure Blob Storage as the data backend and runs as a container on Azure Container Instances.
"""

import logging
import os
from typing import List, Tuple

from blob_storage_client import BlobActivitiesClient
from flask import Flask, jsonify, redirect, render_template, request, url_for

app: Flask = Flask(__name__)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)

logging.getLogger("urllib3").setLevel(logging.WARNING)
logging.getLogger("azure").setLevel(logging.WARNING)
logging.getLogger("werkzeug").setLevel(logging.INFO)

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Global state
activities_client: BlobActivitiesClient = None
activities: List[Tuple[str, str]] = []

username = os.environ.get("LOGIN_NAME", "paolo")
if not username or not username.strip():
    raise ValueError("Username cannot be None or empty")


def create_activity(activity: str | None = None) -> dict:
    """Create an activity document."""
    if not activity or not activity.strip():
        raise ValueError("Activity cannot be None or empty")
    return {
        "username": username,
        "activity": activity,
    }


def read_activities_from_storage(user: str | None = None) -> List[Tuple[str, str]]:
    """Read all activities from Blob Storage."""
    result = []
    try:
        if activities_client and user:
            activity_list = activities_client.read_activities(user)
            for activity in activity_list:
                result.append((activity["id"], activity["activity"]))
    except (ConnectionError, ValueError, KeyError) as e:
        logger.error("Error reading activities: %s", e)
    return result


@app.route("/", methods=["GET", "POST"])
def index():
    """Handle the main page for viewing and adding activities."""
    edit_id = request.args.get("edit_id")
    edit_activity = request.args.get("edit_activity")

    if request.method == "POST":
        activity_text = request.form.get("activity")
        if activity_text:
            try:
                row_id = request.form.get("row_id")
                if row_id:
                    updated = activities_client.update_activity_by_id(
                        row_id, activity_text, username
                    )
                    if updated:
                        logger.info("Activity updated: %s", row_id)
                else:
                    activity_doc = create_activity(activity_text)
                    inserted = activities_client.insert_activity(activity_doc)
                    if inserted:
                        activities.append((inserted["id"], inserted["activity"]))
                        logger.info("Activity created: %s", inserted["id"])
            except (ConnectionError, ValueError) as e:
                logger.error("Error creating/updating activity: %s", e)

        return redirect(url_for("index"))

    # Reload activities from Blob Storage on GET
    activities.clear()
    activities.extend(read_activities_from_storage(username))

    return render_template(
        "index.html",
        activities=activities,
        username=username,
        edit_id=edit_id,
        edit_activity=edit_activity,
    )


@app.route("/favicon.ico")
def favicon():
    """Serve the favicon from the static folder."""
    return app.send_static_file("favicon.ico")


@app.route("/delete/<int:activity_id>", methods=["POST"])
def delete(activity_id: int):
    """Handle deletion of an activity by its index in the list."""
    try:
        if 0 <= activity_id < len(activities):
            db_activity_id = activities[activity_id][0]
            rows_deleted = activities_client.delete_activity_by_id(
                db_activity_id, username
            )
            if rows_deleted > 0:
                logger.info("Activity deleted: %s", db_activity_id)
            else:
                logger.warning("No activity found with ID: %s", db_activity_id)
    except (ConnectionError, ValueError) as e:
        logger.error("Error deleting activity: %s", e)

    return redirect(url_for("index"))


@app.route("/update/<int:activity_id>", methods=["GET"])
def update(activity_id: int):
    """Handle updating of an activity by its index in the list."""
    try:
        if 0 <= activity_id < len(activities):
            db_activity_id = activities[activity_id][0]
            activity_text = activities[activity_id][1]
            return redirect(
                url_for("index", edit_id=db_activity_id, edit_activity=activity_text)
            )
    except (ConnectionError, ValueError) as e:
        logger.error("Error preparing activity for update: %s", e)

    return redirect(url_for("index"))


@app.route("/health")
def health():
    """Health check endpoint for validation."""
    return jsonify({
        "status": "healthy",
        "storage_configured": activities_client is not None,
        "username": username,
    }), 200


# Initialize the Blob Storage client on module load
activities_client = BlobActivitiesClient.from_env()

if activities_client:
    logger.info("Blob Storage client initialized for user: %s", username)
else:
    logger.warning("Blob Storage client not initialized. Running without persistence.")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
