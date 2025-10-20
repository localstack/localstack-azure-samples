"""Flask application for managing vacation activities using Azure Cosmos DB."""
import os
import datetime
import logging
from typing import List, Tuple
from flask import Flask, render_template, request, redirect, url_for
from cosmosdb import CosmosDBClient
import hashlib

# Initialize Flask application
app: Flask = Flask(__name__)

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

# Global variables for Azure and Cosmos DB configuration
cosmosdb_client: CosmosDBClient

debug: bool = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
activities: List[Tuple[int, str]] = []

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
    """Read all documents from the Cosmos DB collection."""
    documents = []
    try:
        if cosmosdb_client:
            activities.clear()
            query = {'username': username} if username else {}
            for document in cosmosdb_client.read_documents(query=query):
                documents.append(document)
                activities.append((document["_id"], document["activity"]))
    except (ConnectionError, ValueError, KeyError) as e:
        logger.error("Error reading documents: %s", e)
    return documents

@app.route('/', methods=['GET', 'POST'])
def index():
    """Handle the main page for viewing and adding activities."""    
    if request.method == 'POST':
        activity = request.form.get('activity')
        if activity:
            try:
                # Create a document with the activity provided
                document: dict = create_document(activity)
                cosmosdb_client.insert_document(document)

                # Append the activity to the activities list
                activities.append((document["_id"], activity))

            except (ConnectionError, ValueError) as e:
                logger.error("Error creating document: %s", e)

        return redirect(url_for('index'))

    # Always reload activities from Cosmos DB on GET (refresh)
    read_documents(username)

    return render_template('index.html', activities=activities, username=username)

@app.route('/delete/<int:activity_id>', methods=['POST'])
def delete(activity_id: int):
    """Handle deletion of an activity by its index."""
    if 0 <= activity_id < len(activities):
        # Delete the document from Cosmos DB
        cosmosdb_client.delete_document_by_id(activities[activity_id][0])

    return redirect(url_for('index'))

# Read debug environment variable
debug = os.environ.get("DEBUG", "false").lower() == "true"

# Initialize the application and Azure services when the module is loaded.
# This ensures that the setup runs regardless of how the app is started
# (e.g., via 'flask run' or directly).
cosmosdb_client = CosmosDBClient.from_env()

# Get username from form or environment variable
username = os.environ.get("USERNAME", "paolo")

# Validate username
if not username or not username.strip():
    raise ValueError("Username cannot be None or empty")

if cosmosdb_client:
    # Read documents from Cosmos DB to populate the activities list
    read_documents(username)

# Run the Flask application
if __name__ == '__main__':
    app.run(debug=debug)

    
