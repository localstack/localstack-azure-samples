"""Flask application for managing vacation activities using Azure SQL Database."""
import logging
import os
from typing import List, Tuple

from activities import ActivitiesHelper
from certificates import get_certificate_info, get_ssl_context_from_keyvault
from flask import Flask, jsonify, redirect, render_template, request, url_for

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

# Global variables for Azure SQL Database configuration
activities_helper: ActivitiesHelper

debug: bool = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
activities: List[Tuple[str, str]] = []

def create_activity(activity: str | None = None) -> dict:
    """Create a activity with activity and timestamp."""

    if not activity or not activity.strip():
        raise ValueError("Activity cannot be None or empty")
    
    return {
        "username": username,
        "activity": activity
    }

def read_activities_from_db(username: str | None = None) -> List[Tuple[str, str]]:
    """Read all activities from the SQL Database."""
    result = []
    try:
        if activities_helper and username:
            activity_list = activities_helper.read_activities(username)
            for activity in activity_list:
                result.append((activity["id"], activity["activity"]))
    except (ConnectionError, ValueError, KeyError) as e:
        logger.error("Error reading activities: %s", e)
    return result

@app.route('/', methods=['GET', 'POST'])
def index():
    """Handle the main page for viewing and adding activities."""
    # Get edit data from query parameters (if any)
    edit_id = request.args.get('edit_id')
    edit_activity = request.args.get('edit_activity')
    
    # Handle form submission. This part is not invoked when clicking the Edit button.
    if request.method == 'POST':
        activity_text = request.form.get('activity')
        if activity_text:
            try:
                row_id = request.form.get('row_id')
                if row_id:
                    # Update existing activity
                    if not row_id.strip():
                        raise ValueError("Row ID cannot be None or empty")

                    updated_activity = activities_helper.update_activity_by_id(row_id, activity_text)
                    if updated_activity:
                        logger.info(f"Activity updated: {row_id}")
                else:
                    # Create an activity document with the activity text provided
                    activity_doc: dict = create_activity(activity_text)
                
                    # Insert the activity into the database
                    inserted_activity = activities_helper.insert_activity(activity_doc)
                    
                    if inserted_activity:
                        # Append the activity to the in-memory list
                        activities.append((inserted_activity["id"], inserted_activity["activity"]))
                        logger.info(f"Activity created: {inserted_activity['id']}")
            except (ConnectionError, ValueError) as e:
                logger.error("Error creating/updating activity: %s", e)

        return redirect(url_for('index'))

    # Always reload activities from SQL Database on GET (refresh)
    activities.clear()
    activities.extend(read_activities_from_db(username))

    return render_template('index.html', activities=activities, username=username, edit_id=edit_id, edit_activity=edit_activity)

@app.route('/favicon.ico')
def favicon():
    """Serve the favicon from the static folder."""
    return app.send_static_file('favicon.ico')

@app.route('/delete/<int:activity_id>', methods=['POST'])
def delete(activity_id: int):
    """Handle deletion of an activity by its index in the list."""
    try:
        if 0 <= activity_id < len(activities):
            db_activity_id = activities[activity_id][0]
            # Delete the activity from SQL Database
            rows_deleted = activities_helper.delete_activity_by_id(db_activity_id)
            
            if rows_deleted > 0:
                logger.info(f"Activity deleted: {db_activity_id}")
            else:
                logger.warning(f"No activity found with ID: {db_activity_id}")
    except (ConnectionError, ValueError) as e:
        logger.error("Error deleting activity: %s", e)

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

@app.route('/api/certificate/validate', methods=['GET'])
def validate_certificate():
    """
    Downloads the certificate from Key Vault, loads it as X509,
    and returns its properties to validate that Key Vault certificate
    emulation works correctly.
    """
    vault_uri = os.environ.get('KEYVAULT_URI')
    cert_name = os.environ.get('CERT_NAME', 'test-cert')

    if not vault_uri:
        return jsonify({"error": "KEYVAULT_URI not configured"}), 500

    try:
        info = get_certificate_info(vault_uri, cert_name)
        return jsonify(info), 200
    except Exception as e:
        logger.error("Error validating certificate: %s", e)
        return jsonify({"error": str(e)}), 500

# Read debug environment variable
debug = os.environ.get("DEBUG", "false").lower() == "true"

# Initialize the application and Azure services when the module is loaded.
# This ensures that the setup runs regardless of how the app is started
# (e.g., via 'flask run' or directly).
activities_helper = ActivitiesHelper.from_env()

# Get username from form or environment variable
username = os.environ.get("LOGIN_NAME", "paolo")

# Validate username
if not username or not username.strip():
    raise ValueError("Username cannot be None or empty")

if activities_helper:
    # Read activities from SQL Database to populate the activities list
    activities.extend(read_activities_from_db(username))
    logger.info(f"Loaded {len(activities)} activities for user: {username}")

# Run the Flask application
if __name__ == '__main__':
    vault_uri = os.environ.get('KEYVAULT_URI')
    cert_name = os.environ.get('CERT_NAME')

    if vault_uri and cert_name:
        ssl_ctx = get_ssl_context_from_keyvault(vault_uri, cert_name)
        app.run(host='0.0.0.0', port=443, ssl_context=ssl_ctx)
    else:
        app.run(debug=debug)