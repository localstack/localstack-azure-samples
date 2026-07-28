"""Operations dashboard for the payment stream.

A read-only control room for the pipeline. Everything on the page is pulled live from the
emulated Azure services, so it doubles as proof that each capability is real:

* **Stream** - per-partition sequence numbers and last-enqueued times, straight from the
  Event Hubs runtime API (`get_partition_properties`).
* **Consumer lag** - the checkpoint blobs the Functions host writes, compared against the
  head of each partition. This is how you answer "is my processor keeping up?".
* **Alerts** - the `fraud-alerts` hub, read from the beginning on each refresh.
* **Capture** - the Avro archives Event Hubs Capture wrote to Blob Storage, decoded in the
  browser so you can see the cold path is real data, not a placeholder.
* **Schemas** - the contracts registered in the Event Hubs Schema Registry.

Run locally:  python app.py       (or gunicorn, as the Web App does)
"""

import io
import json
import os
import threading
from datetime import UTC, datetime
from urllib.parse import urlparse

import fastavro
import requests
from azure.eventhub import EventHubConsumerClient, EventHubProducerClient
from azure.storage.blob import BlobServiceClient
from flask import Flask, jsonify, render_template

app = Flask(__name__)

EVENT_HUB_NAME = os.environ.get("EVENT_HUB_NAME", "payments")
ALERT_HUB_NAME = os.environ.get("ALERT_HUB_NAME", "fraud-alerts")
FRAUD_CONSUMER_GROUP = os.environ.get("FRAUD_CONSUMER_GROUP", "fraud-detector")
CAPTURE_CONTAINER = os.environ.get("CAPTURE_CONTAINER_NAME", "payments-archive")
SCHEMA_GROUP = os.environ.get("SCHEMA_GROUP_NAME", "payments-schemas")
# The contract src/producers/schema_register.py publishes.
SCHEMA_NAME = os.environ.get("SCHEMA_NAME", "PaymentEvent")
API_VERSION = "2023-07-01"
# Upper bound on a single alerts read, so a page refresh can never hang the worker thread.
ALERT_READ_TIMEOUT_SECONDS = 15


def eventhub_connection() -> str:
    return os.environ.get("EVENTHUB_LISTEN_CONNECTION_STRING") or os.environ.get(
        "EVENTHUB_SEND_CONNECTION_STRING", ""
    )


def storage_connection() -> str:
    return os.environ.get("STORAGE_CONNECTION_STRING", "")


def _namespace_host(conn_str: str) -> str:
    for part in conn_str.split(";"):
        if part.startswith("Endpoint="):
            return urlparse(part.split("=", 1)[1]).hostname or ""
    return ""


def partition_snapshot() -> list[dict]:
    """Live per-partition head positions for the payments hub."""
    conn = eventhub_connection()
    if not conn:
        return []
    client = EventHubProducerClient.from_connection_string(conn, eventhub_name=EVENT_HUB_NAME)
    rows = []
    with client:
        for partition_id in client.get_partition_ids():
            properties = client.get_partition_properties(partition_id)
            last_enqueued = properties.get("last_enqueued_time_utc")
            rows.append(
                {
                    "partition": partition_id,
                    "events": properties["last_enqueued_sequence_number"] + 1,
                    "last_sequence_number": properties["last_enqueued_sequence_number"],
                    "last_offset": str(properties.get("last_enqueued_offset")),
                    "last_enqueued": last_enqueued.isoformat() if last_enqueued else None,
                    "is_empty": properties.get("is_empty", False),
                }
            )
    return rows


def checkpoint_snapshot(partitions: list[dict]) -> list[dict]:
    """Checkpoints written by the Functions host, plus the resulting lag per partition."""
    conn = storage_connection()
    if not conn:
        return []
    heads = {row["partition"]: row["last_sequence_number"] for row in partitions}
    rows = []
    service = BlobServiceClient.from_connection_string(conn)
    for container in service.list_containers():
        # The Functions host keeps leases under azure-webjobs-eventhub/...
        if "eventhub" not in container["name"]:
            continue
        container_client = service.get_container_client(container["name"])
        for blob in container_client.list_blobs():
            partition_id = blob.name.rsplit("/", 1)[-1]
            if not partition_id.isdigit():
                continue
            try:
                payload = container_client.download_blob(blob.name).readall()
                metadata = json.loads(payload) if payload else {}
            except Exception:
                metadata = {}
            blob_properties = container_client.get_blob_client(blob.name).get_blob_properties()
            checkpoint_metadata = blob_properties.metadata or {}
            sequence = checkpoint_metadata.get("sequencenumber") or metadata.get("SequenceNumber")
            sequence = int(sequence) if sequence not in (None, "") else None
            head = heads.get(partition_id)
            rows.append(
                {
                    "partition": partition_id,
                    "checkpoint_sequence_number": sequence,
                    "head_sequence_number": head,
                    "lag": (head - sequence) if (head is not None and sequence is not None) else None,
                    "owner": checkpoint_metadata.get("owner", ""),
                    "blob": f"{container['name']}/{blob.name}",
                }
            )
    return sorted(rows, key=lambda row: row["partition"])


def recent_alerts(limit: int = 25) -> list[dict]:
    """Read the fraud-alerts hub from the beginning (the sample keeps volumes small)."""
    conn = eventhub_connection()
    if not conn:
        return []
    client = EventHubConsumerClient.from_connection_string(
        conn, consumer_group="$Default", eventhub_name=ALERT_HUB_NAME
    )
    alerts: list[dict] = []
    lock = threading.Lock()
    drained: set[str] = set()
    caught_up = threading.Event()
    try:
        partitions = set(client.get_partition_ids())
    except Exception:
        partitions = set()

    def collect(partition_context, events):
        if not events:
            # An empty batch after max_wait_time means this partition is drained. Every
            # partition has to report in before returning, otherwise the page would show
            # only the alerts that happened to land on the first one to finish.
            drained.add(partition_context.partition_id)
            if partitions and partitions <= drained:
                caught_up.set()
            return
        with lock:
            for event in events:
                try:
                    alerts.append(json.loads(event.body_as_str()))
                except ValueError:
                    continue

    # receive_batch() returns only once the client is closed, so it runs on a worker thread
    # and this thread does the closing - the pattern scripts/roundtrip_check.py already uses.
    # Calling it inline would deadlock the request: the close can never be reached.
    receiver = threading.Thread(
        target=lambda: client.receive_batch(
            on_event_batch=collect,
            starting_position="-1",
            max_wait_time=3,
            max_batch_size=limit,
        ),
        daemon=True,
    )
    receiver.start()
    caught_up.wait(timeout=ALERT_READ_TIMEOUT_SECONDS)
    client.close()
    receiver.join(timeout=5)
    return alerts[-limit:][::-1]


def capture_snapshot(limit: int = 10) -> dict:
    """List Capture archives and decode the newest one to prove the cold path works."""
    conn = storage_connection()
    if not conn:
        return {"files": [], "sample_records": []}
    service = BlobServiceClient.from_connection_string(conn)
    container_client = service.get_container_client(CAPTURE_CONTAINER)
    files: list[dict] = []
    try:
        for blob in container_client.list_blobs():
            files.append(
                {
                    "name": blob.name,
                    "size": blob.size,
                    "last_modified": blob.last_modified.isoformat() if blob.last_modified else None,
                }
            )
    except Exception:
        return {"files": [], "sample_records": []}

    files.sort(key=lambda item: item["last_modified"] or "", reverse=True)
    sample_records: list[dict] = []
    for candidate in files:
        if candidate["size"] == 0:
            continue
        try:
            payload = container_client.download_blob(candidate["name"]).readall()
            reader = fastavro.reader(io.BytesIO(payload))
            for record in reader:
                body = record.get("Body")
                if isinstance(body, bytes):
                    try:
                        body = json.loads(body.decode("utf-8"))
                    except ValueError:
                        body = body.decode("utf-8", errors="replace")
                sample_records.append(
                    {
                        "sequence_number": record.get("SequenceNumber"),
                        "offset": record.get("Offset"),
                        "enqueued": record.get("EnqueuedTimeUtc"),
                        "body": body,
                    }
                )
                if len(sample_records) >= 5:
                    break
        except Exception:
            continue
        if sample_records:
            break

    return {"files": files[:limit], "sample_records": sample_records}


def schema_snapshot() -> list[dict]:
    """Contracts registered in the Event Hubs Schema Registry."""
    conn = eventhub_connection()
    host = _namespace_host(conn)
    if not host:
        return []
    token = os.environ.get("EVENTHUB_DATAPLANE_TOKEN")
    if not token:
        try:
            from azure.identity import DefaultAzureCredential

            token = DefaultAzureCredential().get_token("https://eventhubs.azure.net/.default").token
        except Exception:
            return []
    # Listing a group's schemas is not part of the Schema Registry data plane. The 2023-07-01
    # spec exposes the versions of a *named* schema, so the panel asks about the contract this
    # sample registers - which keeps it working against real Azure, not just the emulator.
    try:
        response = requests.get(
            f"https://{host}/$schemaGroups/{SCHEMA_GROUP}/schemas/{SCHEMA_NAME}/versions"
            f"?api-version={API_VERSION}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
            # Only the emulator's certificate is self-signed; against real Azure this stays on.
            verify="localhost.localstack.cloud" not in host,
        )
        if not response.ok:
            return []
        versions = response.json().get("Value", [])
        if not versions:
            return []
        return [{"group": SCHEMA_GROUP, "name": SCHEMA_NAME, "versions": len(versions)}]
    except Exception:
        return []


@app.route("/")
def index():
    return render_template("index.html", refreshed=datetime.now(UTC).strftime("%H:%M:%S"))


@app.route("/api/overview")
def overview():
    partitions = partition_snapshot()
    capture = capture_snapshot()
    return jsonify(
        {
            "generated_at": datetime.now(UTC).isoformat(),
            "event_hub": EVENT_HUB_NAME,
            "alert_hub": ALERT_HUB_NAME,
            "consumer_group": FRAUD_CONSUMER_GROUP,
            "total_events": sum(row["events"] for row in partitions),
            "partitions": partitions,
            "checkpoints": checkpoint_snapshot(partitions),
            "alerts": recent_alerts(),
            "capture_files": capture["files"],
            "capture_records": capture["sample_records"],
            "schemas": schema_snapshot(),
        }
    )


@app.route("/health")
def health():
    return jsonify({"status": "healthy"})


if __name__ == "__main__":
    import urllib3

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
