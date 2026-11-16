"""Flask application for managing vacation activities backed by PostgreSQL."""
import datetime
import hashlib
import logging
import os
from typing import List, Tuple

from microsoft.opentelemetry import use_microsoft_opentelemetry

# The logger of the application
LOGGER_NAME = "webapp"

# When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
# Distro sends to Application Insights the requests the app serves, its calls to PostgreSQL, the records of the
# application's logger (traces), the exceptions it logs, the custom events and the custom metric below. It runs before
# Flask and psycopg2 are imported, so that its instrumentations wrap them.
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    use_microsoft_opentelemetry(enable_azure_monitor=True, logger_name=LOGGER_NAME)

from flask import Flask, flash, redirect, render_template, request, url_for
from opentelemetry import metrics

from database import PostgresClient

app: Flask = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(24))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logging.getLogger("urllib3").setLevel(logging.WARNING)
logging.getLogger("werkzeug").setLevel(logging.INFO)
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


def make_activity_id(username: str, activity: str) -> str:
    """MD5 of username + activity + timestamp — preserves the source sample's ID scheme."""
    timestamp = datetime.datetime.now().isoformat()
    return hashlib.md5(f"{username}_{activity}_{timestamp}".encode()).hexdigest()


db_client: PostgresClient = PostgresClient.from_env()
db_client.init_schema()

username = os.environ.get("LOGIN_NAME", "paolo")
if not username or not username.strip():
    raise ValueError("LOGIN_NAME cannot be empty")

activities: List[Tuple[str, str]] = []


def reload_activities() -> bool:
    """Read the activities of the user from the database. Return whether it succeeded."""
    activities.clear()
    try:
        activities.extend(db_client.list_activities(username))
        return True
    except Exception:
        logger.exception("Failed to load activities.")
        return False


@app.route("/", methods=["GET", "POST"])
def index():
    if request.method == "POST":
        activity = request.form.get("activity")
        if activity:
            try:
                row_id = request.form.get("row_id")
                if row_id:
                    if not row_id.strip():
                        raise ValueError("Row ID cannot be empty")
                    if db_client.update_activity(row_id, activity):
                        logger.info("Activity updated: %s", row_id)
                        track_activity_event("ActivityUpdated", "update", row_id)
                        flash("Activity updated!")
                else:
                    activity_id = make_activity_id(username, activity)
                    db_client.insert_activity(activity_id, username, activity)
                    logger.info("Activity added: %s", activity)
                    track_activity_event("ActivityAdded", "add", activity_id)
                    flash("Activity added!")
            except Exception:
                # The distro sends a log record that carries an exception to Application Insights as an exception
                logger.exception("Error writing activity.")
                flash("Failed to save the activity.")

        return redirect(url_for("index"))

    if not reload_activities():
        flash("Failed to load the activities.")
    return render_template("index.html", activities=activities, username=username)


@app.route("/favicon.ico")
def favicon():
    return app.send_static_file("favicon.ico")


@app.route("/delete/<int:activity_id>", methods=["POST"])
def delete(activity_id: int):
    if 0 <= activity_id < len(activities):
        row_id = activities[activity_id][0]
        try:
            db_client.delete_activity(row_id)
            logger.info("Activity deleted: %s", row_id)
            track_activity_event("ActivityDeleted", "delete", row_id)
            flash("Activity deleted.")
        except Exception:
            logger.exception("Error deleting activity %s.", row_id)
            flash("Failed to delete the activity.")
    return redirect(url_for("index"))


debug = os.environ.get("DEBUG", "false").lower() == "true"

reload_activities()

if __name__ == "__main__":
    app.run(debug=debug)
