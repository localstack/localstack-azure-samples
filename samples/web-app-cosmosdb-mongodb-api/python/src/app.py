"""Flask application for managing vacation activities using MongoDB."""
import os
import datetime
import logging
from typing import List, Tuple
from flask import Flask, render_template, request, redirect, url_for
from mongodb import MongoDbClient
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

# Global variables for MongoDB configuration
mongodb_client: MongoDbClient

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
    """Read all documents from the MongoDB collection."""
    documents = []
    try:
        if mongodb_client:
            activities.clear()
            query = {'username': username} if username else {}
            for document in mongodb_client.read_documents(query=query):
                documents.append(document)
                activities.append((document["_id"], document["activity"]))
    except (ConnectionError, ValueError, KeyError) as e:
        logger.error("Error reading documents: %s", e)
    return documents

@app.route('/', methods=['GET', 'POST'])
def index():
    """Handle the main page for viewing and adding activities."""
    # Get edit data from query parameters (if any)
    edit_id = request.args.get('edit_id')
    edit_activity = request.args.get('edit_activity')
    
    if request.method == 'POST':
        activity = request.form.get('activity')
        if activity:
            try:
                row_id = request.form.get('row_id')
                if row_id:
                    # Update existing activity
                    if not row_id.strip():
                        raise ValueError("Row ID cannot be None or empty")

                    updated_activity = mongodb_client.update_document_by_id(row_id, {"activity": activity})
                    if updated_activity:
                        logger.info(f"Activity updated: {row_id}")
                else:
                    # Create a document with the activity provided
                    document: dict = create_document(activity)
                    mongodb_client.insert_document(document)

                    # Append the activity to the activities list
                    activities.append((document["_id"], activity))
                    logger.info(f"Activity added: {activity}")

            except (ConnectionError, ValueError) as e:
                logger.error("Error creating document: %s", e)

        return redirect(url_for('index'))

    # Always reload activities from Cosmos DB on GET (refresh)
    read_documents(username)

    return render_template('index.html', activities=activities, username=username, edit_id=edit_id, edit_activity=edit_activity)

@app.route('/favicon.ico')
def favicon():
    """Serve the favicon from the static folder."""
    return app.send_static_file('favicon.ico')

@app.route('/delete/<int:activity_id>', methods=['POST'])
def delete(activity_id: int):
    """Handle deletion of an activity by its index."""
    if 0 <= activity_id < len(activities):
        # Delete the document from MongoDB
        mongodb_client.delete_document_by_id(activities[activity_id][0])

    return redirect(url_for('index'))

@app.route('/update/<int:activity_id>', methods=['GET'])
def update(activity_id: int):
    """Handle updating of an activity by its index in the list."""
    try:
        if 0 <= activity_id < len(activities):
            db_activity_id = activities[activity_id][0]
            activity_text = activities[activity_id][1]
            # Redirect to index with edit parameters
            return redirect(url_for('index', edit_id=db_activity_id, edit_activity=activity_text))
    except (ConnectionError, ValueError) as e:
        logger.error("Error preparing activity for update: %s", e)

    return redirect(url_for('index'))

# Read debug environment variable
debug = os.environ.get("DEBUG", "false").lower() == "true"

# Initialize the application and MongoDB client when the module is loaded.
# This ensures that the setup runs regardless of how the app is started
# (e.g., via 'flask run' or directly).
mongodb_client = MongoDbClient.from_env()

# Get username from form or environment variable
username = os.environ.get("LOGIN_NAME", "paolo")

# Validate username
if not username or not username.strip():
    raise ValueError("Username cannot be None or empty")

if mongodb_client:
    # Read documents from MongoDB to populate the activities list
    read_documents(username)

# Run the Flask application
if __name__ == '__main__':
    app.run(debug=debug)
