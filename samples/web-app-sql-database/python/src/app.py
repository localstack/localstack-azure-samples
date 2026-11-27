"""Flask application for managing vacation activities using Azure SQL Database."""
import logging
import os
from typing import List, Tuple

import pyodbc
from microsoft.opentelemetry import use_microsoft_opentelemetry

# The logger of the application: the loggers of the other modules are its children
LOGGER_NAME = "webapp"

# When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
# Distro sends to Application Insights the requests the app serves, its calls to Key Vault, the records of the
# application's loggers (traces), the exceptions they log, the custom events and the custom metric below. It runs
# before Flask is imported, so that its instrumentation wraps it.
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    use_microsoft_opentelemetry(enable_azure_monitor=True, logger_name=LOGGER_NAME)

    # The distro instruments no ODBC driver: the generic DB-API instrumentation wraps pyodbc.connect, so that the
    # statements the app runs on Azure SQL Database arrive as dependencies too
    from opentelemetry.instrumentation.dbapi import trace_integration

    trace_integration(pyodbc, "connect", "mssql")

from activities import ActivitiesHelper  # noqa: E402
from certificates import get_certificate_info, get_ssl_context_from_keyvault  # noqa: E402
from flask import Flask, flash, jsonify, redirect, render_template, request, url_for  # noqa: E402
from opentelemetry import metrics  # noqa: E402

# Initialize Flask application
app: Flask = Flask(__name__)
app.secret_key = os.environ.get('FLASK_SECRET_KEY', os.urandom(24))

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


def track_activity_event(event_name: str, operation: str, activity_id: str) -> None:
    """Send a custom event (customEvents table) and count the operation in the custom metric."""
    # The Microsoft OpenTelemetry Distro sends a log record that carries the microsoft.custom_event.name attribute as a
    # custom event named after its value, with the other attributes as its custom dimensions.
    logger.info(
        f"{event_name}: {activity_id}",
        extra={"microsoft.custom_event.name": event_name, "activity.id": activity_id},
    )
    activity_counter.add(1, {"operation": operation})

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
            logger.info("Activities read: %d", len(result))
    except (pyodbc.Error, ConnectionError, ValueError, KeyError):
        # The distro sends a log record that carries an exception to Application Insights as an exception
        logger.exception("Error reading activities.")
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
                        flash('Activity updated.')
                        logger.info("Activity updated: %s (%s)", row_id, activity_text)
                        track_activity_event("ActivityUpdated", "update", row_id)
                    else:
                        logger.warning("Activity not found: %s", row_id)
                        flash('Activity not found.')
                else:
                    # Create an activity document with the activity text provided
                    activity_doc: dict = create_activity(activity_text)
                
                    # Insert the activity into the database
                    inserted_activity = activities_helper.insert_activity(activity_doc)
                    
                    if inserted_activity:
                        # Append the activity to the in-memory list
                        activities.append((inserted_activity["id"], inserted_activity["activity"]))
                        flash('Activity added.')
                        logger.info("Activity added: %s (%s)", inserted_activity["id"], inserted_activity["activity"])
                        track_activity_event("ActivityAdded", "add", inserted_activity["id"])
                    else:
                        logger.error("The database returned no row for the new activity.")
                        flash('Failed to save the activity.')
            except (pyodbc.Error, ConnectionError, ValueError):
                logger.exception("Error creating/updating activity.")

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
                flash('Activity deleted.')
                logger.info("Activity deleted: %s", db_activity_id)
                track_activity_event("ActivityDeleted", "delete", db_activity_id)
            else:
                logger.warning("Activity not found: %s", db_activity_id)
                flash('Activity not found.')
        else:
            logger.warning("Activity not found: position %d", activity_id)
    except (pyodbc.Error, ConnectionError, ValueError):
        logger.exception("Error deleting activity.")

    return redirect(url_for('index'))

@app.route('/update/<int:activity_id>', methods=['GET'])
def update(activity_id: int):
    """Handle updating of an activity by its index in the list."""
    try:
        if 0 <= activity_id < len(activities):
            db_activity_id = activities[activity_id][0]
            activity_text = activities[activity_id][1]
            logger.info("Activity read: %s (%s)", db_activity_id, activity_text)
            # Redirect to index with edit parameters
            return redirect(url_for('index', edit_id=db_activity_id, edit_activity=activity_text))
        logger.warning("Activity not found: position %d", activity_id)
    except (ConnectionError, ValueError):
        logger.exception("Error preparing activity for update.")

    return redirect(url_for('index'))

@app.route('/api/certificate', methods=['GET'])
def validate_certificate():
    """
    Downloads the certificate from Key Vault, loads it as X509,
    and returns its properties to validate that Key Vault certificate
    emulation works correctly.
    """
    vault_uri = os.environ.get('KEYVAULT_URI')
    cert_name = os.environ.get('CERT_NAME')

    if not vault_uri or not cert_name:
        return jsonify({"error": "KEYVAULT_URI not configured"}), 500

    try:
        info = get_certificate_info(vault_uri, cert_name)
        logger.info("Certificate read: %s (thumbprint %s)", info["name"], info["thumbprint"])
        return jsonify(info), 200
    except Exception as e:
        logger.exception("Error validating certificate.")
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
        app.run(host='0.0.0.0', port=8443, ssl_context=ssl_ctx)
    else:
        app.run(debug=debug)