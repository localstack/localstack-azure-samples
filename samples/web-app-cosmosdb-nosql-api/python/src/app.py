import os
import datetime
import logging
import hashlib

from microsoft.opentelemetry import use_microsoft_opentelemetry

# The logger of the application
LOGGER_NAME = "webapp"

# When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
# Distro sends to Application Insights the requests the app serves, its calls to Azure Cosmos DB (the distro traces the
# Azure SDKs), the records of the application's logger (traces), the exceptions it logs, the custom events and the
# custom metric below. It runs before Flask is imported, so that its Flask instrumentation wraps the application.
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    use_microsoft_opentelemetry(enable_azure_monitor=True, logger_name=LOGGER_NAME)

from flask import Flask, flash, render_template, request, redirect, url_for
from opentelemetry import metrics

from cosmosdb_client import CosmosDbClient


app = Flask(__name__)
app.secret_key = os.environ.get('FLASK_SECRET_KEY', os.urandom(24))
app.debug = True

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

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

logger.info("Loading app")

cosmos_client = None
activities = None

username = os.environ.get("LOGIN_NAME", "alex")
if not username.strip():
    raise ValueError("Username cannot be empty")

def get_activities():
    global activities
    if activities is None:
        logger.info("Initializing Activities data structure")
        activities = set()
    return activities

def get_cosmos():
    global cosmos_client
    if cosmos_client is None:
        logger.info("Initializing Cosmos client")
        cosmos_client = CosmosDbClient.from_env()
    return cosmos_client

def create_document(activity: str) -> dict:
    get_cosmos().ensure_initialized()
    
    timestamp = datetime.datetime.now().isoformat()
    id_string = f"{username}_{activity}_{timestamp}"
    document_id = hashlib.md5(id_string.encode()).hexdigest()

    return {
        "id": document_id,
        "username": username,
        "activity": activity,
        "timestamp": timestamp
    }

def read_documents(username: str):
    get_cosmos().ensure_initialized()
    get_activities().clear()

    try:
        docs = get_cosmos().read_documents(username)
        for d in docs:
            get_activities().add((d["id"], d["activity"]))
        logger.info("Activities read: %d", len(docs))
        return docs
    except Exception:
        # The distro sends a log record that carries an exception to Application Insights as an exception
        logger.exception("Cosmos read failed.")
        flash("Failed to load the activities.")
        return []


@app.route('/', methods=['GET', 'POST'])
def index():
    edit_id = request.args.get('edit_id')
    edit_activity = request.args.get('edit_activity')

    if request.method == 'POST':
        activity = request.form.get('activity')
        row_id = request.form.get('row_id')

        if activity:
            try:
                if row_id:
                    updated = get_cosmos().update_document_by_id(
                        doc_id=row_id,
                        username=username,
                        updates={"activity": activity}
                    )
                    if updated is not None:
                        logger.info("Activity updated: %s (%s)", row_id, activity)
                        track_activity_event("ActivityUpdated", "update", row_id)
                        flash('Activity updated.')
                    else:
                        logger.warning("Activity not found: %s", row_id)
                        flash('Activity not found.')
                else:
                    doc = create_document(activity)
                    get_cosmos().insert_document(doc)
                    get_activities().add((doc["id"], activity))
                    logger.info("Activity added: %s (%s)", doc["id"], activity)
                    track_activity_event("ActivityAdded", "add", doc["id"])
                    flash('Activity added.')
            except Exception:
                logger.exception("Error writing activity.")
                flash('Failed to save the activity.')

        return redirect(url_for('index'))
    
    read_documents(username)
    
    return render_template(
        'index.html',
        activities=get_activities(),
        username=username,
        edit_id=edit_id,
        edit_activity=edit_activity
    )

@app.route('/delete/<string:activity_id>', methods=['POST'])
def delete(activity_id: str):
    logger.info(f"Deleting activity with ID: {activity_id}")
    
    # Direct deletion using the ID passed in the URL
    try:
        if get_cosmos().delete_document_by_id(activity_id, username):
            logger.info("Activity deleted: %s", activity_id)
            track_activity_event("ActivityDeleted", "delete", activity_id)
            flash('Activity deleted.')
        else:
            logger.warning("Activity not found: %s", activity_id)
            flash('Activity not found.')
    except Exception:
        logger.exception("Error deleting activity %s.", activity_id)
        flash('Failed to delete the activity.')
    
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(debug=True)
