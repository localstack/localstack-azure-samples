import logging
import os
import socket

from microsoft.opentelemetry import use_microsoft_opentelemetry

# The logger of the application
LOGGER_NAME = "webapp"

# When App Service passes the connection string of the Application Insights resource, the Microsoft OpenTelemetry
# Distro sends to Application Insights the requests the app serves, the records of the application's logger (traces),
# the exceptions of the requests that fail, and the custom event and the custom metric below. It runs before the
# application imports Flask, so that its Flask instrumentation wraps the application.
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    use_microsoft_opentelemetry(enable_azure_monitor=True, logger_name=LOGGER_NAME)

from flask import Flask, jsonify, render_template
from opentelemetry import metrics

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(LOGGER_NAME)
logger.setLevel(logging.INFO)

# The custom metric: the number of status requests the app answered, by image (customMetrics table)
status_counter = metrics.get_meter(LOGGER_NAME).create_counter(
    "status_requests", unit="{request}", description="The number of status requests the app answered."
)

app = Flask(__name__)


def app_name() -> str:
    return os.environ.get("APP_NAME", "Custom Image Web App")


def image_name() -> str:
    return os.environ.get("IMAGE_NAME", "custom-image-webapp:v1")


@app.route("/")
def index():
    logger.info("Serving the home page of the %s image", image_name())
    return render_template(
        "index.html",
        app_name=app_name(),
        image_name=image_name(),
        hostname=socket.gethostname(),
    )


@app.route("/api/status")
def status():
    image = image_name()
    hostname = socket.gethostname()
    # A custom event (customEvents table): the Microsoft OpenTelemetry Distro sends a log record that carries the
    # microsoft.custom_event.name attribute as a custom event named after its value, with the other attributes as its
    # custom dimensions
    logger.info(
        f"StatusRequested: {image}",
        extra={"microsoft.custom_event.name": "StatusRequested", "image.name": image, "hostname": hostname},
    )
    status_counter.add(1, {"image": image})
    return jsonify(
        {
            "status": "ok",
            "app": app_name(),
            "image": image,
            "hostname": hostname,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "80")))
