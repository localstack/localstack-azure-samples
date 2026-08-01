import json
import logging
import os
import urllib.request

import azure.functions as func

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
    logging.info("AbuseScan: %s -> %s (web %s)", body["code"], verdict, status)


@app.function_name(name="QrGenerator")
@app.queue_trigger(arg_name="qmsg", queue_name="qrjobs", connection="QrStorage")
def qr_generator(qmsg: func.QueueMessage):
    body = json.loads(qmsg.get_body().decode("utf-8"))
    status = call_web("/internal/generate-qr", {"code": body["code"]})
    logging.info("QrGenerator: %s (web %s)", body["code"], status)
