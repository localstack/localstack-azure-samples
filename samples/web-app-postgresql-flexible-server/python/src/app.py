"""Flask application for managing vacation activities backed by PostgreSQL."""
import datetime
import hashlib
import logging
import os
from typing import List, Tuple

from flask import Flask, flash, redirect, render_template, request, url_for

from database import PostgresClient

app: Flask = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", os.urandom(24))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logging.getLogger("urllib3").setLevel(logging.WARNING)
logging.getLogger("werkzeug").setLevel(logging.INFO)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


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


def reload_activities() -> None:
    activities.clear()
    try:
        activities.extend(db_client.list_activities(username))
    except Exception as exc:
        logger.error("Failed to load activities: %s", exc)


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
                        flash("Activity updated!")
                else:
                    activity_id = make_activity_id(username, activity)
                    db_client.insert_activity(activity_id, username, activity)
                    logger.info("Activity added: %s", activity)
                    flash("Activity added!")
            except (ConnectionError, ValueError) as e:
                logger.error("Error writing activity: %s", e)

        return redirect(url_for("index"))

    reload_activities()
    return render_template("index.html", activities=activities, username=username)


@app.route("/favicon.ico")
def favicon():
    return app.send_static_file("favicon.ico")


@app.route("/delete/<int:activity_id>", methods=["POST"])
def delete(activity_id: int):
    if 0 <= activity_id < len(activities):
        db_client.delete_activity(activities[activity_id][0])
        flash("Activity deleted.")
    return redirect(url_for("index"))


debug = os.environ.get("DEBUG", "false").lower() == "true"

reload_activities()

if __name__ == "__main__":
    app.run(debug=debug)
