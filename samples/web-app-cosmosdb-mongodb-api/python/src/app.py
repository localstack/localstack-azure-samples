"""Flask application for managing vacation activities using MongoDB."""
import os
import datetime
import logging
import threading
from typing import List, Tuple

from microsoft.opentelemetry import use_microsoft_opentelemetry
from opentelemetry.instrumentation.pymongo import PymongoInstrumentor

# The logger of the application
LOGGER_NAME = "webapp"

# When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
# Distro sends to Application Insights the requests the app serves, the records of the application's logger (traces),
# the exceptions it logs, the custom events and the custom metric below. The distro doesn't instrument PyMongo, so the
# OpenTelemetry instrumentation of PyMongo adds the commands sent to Azure Cosmos DB for MongoDB. Both run before Flask
# and PyMongo are imported, so that their instrumentations wrap them.
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    use_microsoft_opentelemetry(enable_azure_monitor=True, logger_name=LOGGER_NAME)
    PymongoInstrumentor().instrument()

from flask import Flask, flash, render_template, request, redirect, url_for
from opentelemetry import metrics
from pymongo.errors import PyMongoError
from mongodb import MongoDbClient
import hashlib

# Initialize Flask application
app: Flask = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(24))

# Configure logging
logging.basicConfig(
    level=logging.INFO,  # Set root logger to INFO to see all application logs
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Set external libraries to WARNING level to reduce noise
logging.getLogger('urllib3').setLevel(logging.WARNING)
logging.getLogger('azure').setLevel(logging.WARNING)

# Keep werkzeug (Flask) at INFO to see requests and enable VSCode browser popup
logging.getLogger('werkzeug').setLevel(logging.INFO)

# Get application logger
logger = logging.getLogger(LOGGER_NAME)
logger.setLevel(logging.INFO)

# The custom metric: the number of activities added, updated and deleted, by operation (customMetrics table)
activity_counter = metrics.get_meter(LOGGER_NAME).create_counter(
    "activities", unit="{activity}", description="The number of activities added, updated and deleted."
)

# The MongoDB client is created by the first request that needs it, not when the module is loaded, so the web app
# starts even when the database is not reachable yet, for example while Azure Cosmos DB for MongoDB upgrades the
# server version of the account. A request that finds the database unavailable shows an error, and the next request
# tries again.
mongodb_client: MongoDbClient | None = None
mongodb_client_lock = threading.Lock()
DATABASE_UNAVAILABLE = "The database is not available. Try again in a minute."

debug: bool = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
activities: List[Tuple[int, str]] = []


def get_mongodb_client() -> MongoDbClient | None:
    """Return the MongoDB client, creating it on first use, or None while the database is not available."""
    global mongodb_client
    with mongodb_client_lock:
        if mongodb_client is None:
            try:
                mongodb_client = MongoDbClient.from_env()
            except PyMongoError:
                # The distro sends a log record that carries an exception to Application Insights as an exception
                logger.exception("The database is not available.")
        return mongodb_client


def track_activity_event(event_name: str, operation: str, activity_id: str) -> None:
    """Send a custom event (customEvents table) and count the operation in the custom metric."""
    # The Microsoft OpenTelemetry Distro sends a log record that carries the microsoft.custom_event.name attribute as a
    # custom event named after its value, with the other attributes as its custom dimensions.
    logger.info(
        f"{event_name}: {activity_id}",
        extra={"microsoft.custom_event.name": event_name, "activity.id": activity_id},
    )
    activity_counter.add(1, {"operation": operation})

def create_document(activity: str | None = None) -> dict:
    """Create a document with activity and timestamp."""

    if not activity or not activity.strip():
        raise ValueError("Activity cannot be None or empty")

    # Generate a unique ID using hash of username, activity, and current timestamp
    timestamp = datetime.datetime.now().isoformat()
    id_string = f"{username}_{activity}_{timestamp}"
    document_id = hashlib.md5(id_string.encode()).hexdigest()
    
    return {
        "_id": document_id,
        "username": username,
        "activity": activity,
        "timestamp": timestamp
    }

def read_documents(username: str | None = None) -> List[dict]:
    """Read all documents from the MongoDB collection."""
    documents = []
    activities.clear()
    client = get_mongodb_client()
    if client is None:
        flash(DATABASE_UNAVAILABLE)
        return documents
    try:
        query = {'username': username} if username else {}
        for document in client.read_documents(query=query):
            documents.append(document)
            activities.append((document["_id"], document["activity"]))
    except PyMongoError:
        logger.exception("Error reading documents.")
        flash(DATABASE_UNAVAILABLE)
    except (ConnectionError, ValueError, KeyError):
        logger.exception("Error reading documents.")
        flash("Failed to load the activities.")
    return documents

@app.route('/', methods=['GET', 'POST'])
def index():
    """Handle the main page for viewing and adding activities."""
    if request.method == 'POST':
        activity = request.form.get('activity')
        client = get_mongodb_client() if activity else None
        if activity and client is None:
            flash(DATABASE_UNAVAILABLE)
        elif activity:
            try:
                row_id = request.form.get('row_id')
                if row_id:
                    # Update existing activity
                    if not row_id.strip():
                        raise ValueError("Row ID cannot be None or empty")

                    updated_activity = client.update_document_by_id(row_id, {"activity": activity})
                    if updated_activity:
                        logger.info(f"Activity updated: {row_id}")
                        track_activity_event("ActivityUpdated", "update", row_id)
                        flash("Activity updated!")
                else:
                    # Create a document with the activity provided
                    document: dict = create_document(activity)
                    client.insert_document(document)

                    # Append the activity to the activities list
                    activities.append((document["_id"], activity))
                    logger.info(f"Activity added: {activity}")
                    track_activity_event("ActivityAdded", "add", document["_id"])
                    flash("Activity added!")

            except PyMongoError:
                logger.exception("Error saving the activity.")
                flash(DATABASE_UNAVAILABLE)
            except (ConnectionError, ValueError):
                logger.exception("Error creating document.")
                flash("Failed to save the activity.")

        return redirect(url_for('index'))

    # Always reload activities from Cosmos DB on GET (refresh)
    read_documents(username)

    return render_template('index.html', activities=activities, username=username)

@app.route('/favicon.ico')
def favicon():
    """Serve the favicon from the static folder."""
    return app.send_static_file('favicon.ico')

@app.route('/delete/<int:activity_id>', methods=['POST'])
def delete(activity_id: int):
    """Handle deletion of an activity by its index."""
    if 0 <= activity_id < len(activities):
        client = get_mongodb_client()
        if client is None:
            flash(DATABASE_UNAVAILABLE)
        else:
            document_id = activities[activity_id][0]
            try:
                # Delete the document from MongoDB
                client.delete_document_by_id(document_id)
                logger.info("Activity deleted: %s", document_id)
                track_activity_event("ActivityDeleted", "delete", document_id)
                flash("Activity deleted.")
            except PyMongoError:
                logger.exception("Error deleting the activity %s.", document_id)
                flash(DATABASE_UNAVAILABLE)

    return redirect(url_for('index'))

# Read debug environment variable
debug = os.environ.get("DEBUG", "false").lower() == "true"

# Validate the configuration when the module is loaded, so that a misconfigured deployment fails at startup,
# regardless of how the app is started (e.g., via 'flask run' or directly). The database is reached later, by the
# first request that needs it (see get_mongodb_client).
if not (os.environ.get("COSMOSDB_CONNECTION_STRING") or os.environ.get("MONGODB_CONNECTION_STRING")):
    raise ValueError("Missing required environment variable: COSMOSDB_CONNECTION_STRING or MONGODB_CONNECTION_STRING")

# Get username from form or environment variable
username = os.environ.get("LOGIN_NAME", "paolo")

# Validate username
if not username or not username.strip():
    raise ValueError("Username cannot be None or empty")

# Run the Flask application
if __name__ == '__main__':
    app.run(debug=debug)
