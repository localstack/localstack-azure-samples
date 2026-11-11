"""Flask application for managing vacation activities using MongoDB."""
import os
import datetime
import logging
import threading
from typing import List, Tuple
from flask import Flask, flash, render_template, request, redirect, url_for
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
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

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
            except PyMongoError as e:
                logger.error("The database is not available: %s", e)
        return mongodb_client

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
    except PyMongoError as e:
        logger.error("Error reading documents: %s", e)
        flash(DATABASE_UNAVAILABLE)
    except (ConnectionError, ValueError, KeyError) as e:
        logger.error("Error reading documents: %s", e)
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
                        flash("Activity updated!")
                else:
                    # Create a document with the activity provided
                    document: dict = create_document(activity)
                    client.insert_document(document)

                    # Append the activity to the activities list
                    activities.append((document["_id"], activity))
                    logger.info(f"Activity added: {activity}")
                    flash("Activity added!")

            except PyMongoError as e:
                logger.error("Error saving the activity: %s", e)
                flash(DATABASE_UNAVAILABLE)
            except (ConnectionError, ValueError) as e:
                logger.error("Error creating document: %s", e)

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
            try:
                # Delete the document from MongoDB
                client.delete_document_by_id(activities[activity_id][0])
                flash("Activity deleted.")
            except PyMongoError as e:
                logger.error("Error deleting the activity: %s", e)
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
