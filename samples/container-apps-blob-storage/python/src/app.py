"""Flask application for a guestbook backed by Azure Blob Storage.

This is the Azure Container Apps variant of the sample apps.
It stores guestbook entries as a JSON blob in Azure Blob Storage and runs as a
container app behind the environment's HTTP ingress. The APP_REVISION env var
is surfaced in the UI and the /health endpoint so revision switches performed
with `az containerapp update` are observable over HTTP.
"""

import logging
import os

from blob_storage_client import BlobGuestbookClient
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
guestbook_client: BlobGuestbookClient | None = None

app_revision = os.environ.get("APP_REVISION", "v1")


@app.route("/", methods=["GET", "POST"])
def index():
    """Handle the main page for viewing and signing the guestbook."""
    if request.method == "POST":
        author = request.form.get("author")
        message = request.form.get("message")
        if author and message and guestbook_client:
            try:
                entry = guestbook_client.insert_entry(author, message)
                logger.info("Entry created: %s", entry["id"])
            except (ConnectionError, ValueError) as e:
                logger.error("Error creating entry: %s", e)

        return redirect(url_for("index"))

    entries = []
    try:
        if guestbook_client:
            entries = guestbook_client.read_entries()
    except (ConnectionError, ValueError, KeyError) as e:
        logger.error("Error reading entries: %s", e)

    return render_template(
        "index.html",
        entries=entries,
        app_revision=app_revision,
    )


@app.route("/delete/<entry_id>", methods=["POST"])
def delete(entry_id: str):
    """Handle deletion of an entry by its ID."""
    try:
        if guestbook_client:
            deleted = guestbook_client.delete_entry_by_id(entry_id)
            if deleted > 0:
                logger.info("Entry deleted: %s", entry_id)
            else:
                logger.warning("No entry found with ID: %s", entry_id)
    except (ConnectionError, ValueError) as e:
        logger.error("Error deleting entry: %s", e)

    return redirect(url_for("index"))


@app.route("/health")
def health():
    """Health check endpoint for validation."""
    return jsonify(
        {
            "status": "healthy",
            "revision": app_revision,
            "storage_configured": guestbook_client is not None,
        }
    ), 200


# Initialize the Blob Storage client on module load
guestbook_client = BlobGuestbookClient.from_env()

if guestbook_client:
    logger.info("Blob Storage client initialized (revision: %s)", app_revision)
else:
    logger.warning("Blob Storage client not initialized. Running without persistence.")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
