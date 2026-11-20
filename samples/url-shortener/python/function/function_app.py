import json
import logging
import os
import urllib.request

import azure.functions as func
from opentelemetry import metrics

# The logger of the functions. With the APPLICATIONINSIGHTS_CONNECTION_STRING app setting, telemetryMode set to
# OpenTelemetry in host.json and PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY set to true, the Python worker sends to
# Application Insights the records of the logger that PYTHON_APPLICATIONINSIGHTS_LOGGER_NAME names (traces), the
# exceptions it logs, the custom event and the custom metric below.
LOGGER_NAME = "function_app"
logger = logging.getLogger(LOGGER_NAME)
logger.setLevel(logging.INFO)

# The custom metric: the number of links the abuse scan checked, by verdict (customMetrics table)
link_scans = metrics.get_meter(LOGGER_NAME).create_counter(
    "link_scans", unit="{link}", description="The number of links the abuse scan checked."
)

app = func.FunctionApp()

SUSPICIOUS = ("phishing", "malware", "casino", "ransom")


def call_web(path, payload):
    """POST to the web app's internal API (shared-token auth)."""
    url = f"{os.environ['WEB_BASE_URL'].rstrip('/')}{path}"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Internal-Token": os.environ["INTERNAL_TOKEN"],
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.status


@app.function_name(name="AbuseScan")
@app.service_bus_queue_trigger(
    arg_name="msg", queue_name="link-events", connection="ServiceBusConnection"
)
def abuse_scan(msg: func.ServiceBusMessage):
    body = json.loads(msg.get_body().decode("utf-8"))
    verdict = "flagged" if any(w in body["url"].lower() for w in SUSPICIOUS) else "clean"
    status = call_web("/internal/scan-result", {"code": body["code"], "verdict": verdict})
    # A custom event (customEvents table): the worker sends a log record that carries the microsoft.custom_event.name
    # attribute as a custom event named after its value, with the other attributes as its custom dimensions
    logger.info(
        f"LinkScanned: {body['code']} -> {verdict}",
        extra={"microsoft.custom_event.name": "LinkScanned", "link.code": body["code"], "scan.verdict": verdict},
    )
    link_scans.add(1, {"verdict": verdict})
    if verdict == "flagged":
        logger.warning("AbuseScan flagged %s", body["code"])
    logger.info("AbuseScan: %s -> %s (web %s)", body["code"], verdict, status)


@app.function_name(name="QrGenerator")
@app.queue_trigger(arg_name="qmsg", queue_name="qrjobs", connection="QrStorage")
def qr_generator(qmsg: func.QueueMessage):
    body = json.loads(qmsg.get_body().decode("utf-8"))
    status = call_web("/internal/generate-qr", {"code": body["code"]})
    logger.info("QrGenerator: %s (web %s)", body["code"], status)
