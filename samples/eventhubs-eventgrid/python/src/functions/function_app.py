"""Cold-path automation: process each Capture archive the moment it lands.

The hot path reacts to individual events. This is the *cold* path, and it is driven entirely by
Azure telling us when a batch is ready:

    telemetry hub --(Capture, 60s windows)--> Avro archive in Blob Storage
                                                   |
                                   Event Hubs raises Microsoft.EventHub.CaptureFileCreated
                                                   |
                                            Event Grid system topic
                                                   |
                                 subscription with an EventHub destination
                                                   |
                                        capture-notifications hub
                                                   |
                                      THIS FUNCTION (Event Hubs trigger)
                                                   |
                            downloads the archive, aggregates it, and writes
                            one summary per device to the curated hub
                                        (Event Hubs output binding)

Why this shape rather than a plain stream processor: the archive is already batched, ordered and
durable, so the aggregation reads whole windows instead of guessing batch boundaries, and it can
be replayed from Blob Storage at any time. That is the pattern behind Microsoft's own "stream big
data into a data warehouse" tutorial.
https://learn.microsoft.com/en-us/azure/event-grid/event-schema-event-hubs
"""

import json
import logging
import os
from datetime import UTC, datetime
from typing import Any, List
from urllib.parse import unquote, urlparse

import azure.functions as func

app = func.FunctionApp()

CAPTURE_FILE_CREATED = "Microsoft.EventHub.CaptureFileCreated"
# A reading at or above this is reported as an excursion on the device's summary.
TEMPERATURE_LIMIT = float(os.environ.get("TEMPERATURE_LIMIT", "80"))


@app.function_name(name="CaptureProcessor")
@app.event_hub_message_trigger(
    arg_name="notifications",
    event_hub_name="%NOTIFICATION_HUB_NAME%",
    connection="EVENTHUB_NOTIFICATION_CONNECTION",
    consumer_group="%CAPTURE_CONSUMER_GROUP%",
    # Cardinality.MANY delivers a list; the default (ONE) delivers a bare EventHubEvent and the
    # handler below would fail with "'EventHubEvent' object is not iterable".
    cardinality=func.Cardinality.MANY,
)
@app.event_hub_output(
    arg_name="curated",
    event_hub_name="%CURATED_HUB_NAME%",
    connection="EVENTHUB_CURATED_CONNECTION",
)
def CaptureProcessor(notifications: List[func.EventHubEvent], curated: func.Out[List[str]]) -> None:
    """Turn every CaptureFileCreated notification into per-device summaries."""
    summaries: list[str] = []

    for notification in notifications:
        for event in _event_grid_batch(notification):
            if event.get("eventType") != CAPTURE_FILE_CREATED:
                # The subscription is scoped to the namespace, so unrelated system events would
                # arrive here too if Azure ever adds more for Event Hubs.
                continue
            data = event.get("data") or {}
            try:
                readings = _read_archive(data["fileUrl"])
            except Exception:
                # A summary is derived data: losing one archive must not park the notification
                # and re-deliver it forever. Log loudly and move on.
                logging.exception("CAPTURE_ARCHIVE_UNREADABLE url=%s", data.get("fileUrl"))
                continue

            summaries.extend(
                json.dumps(summary) for summary in _summarize(readings, data, event["subject"])
            )

    logging.info("CAPTURE_BATCH notifications=%d summaries=%d", len(notifications), len(summaries))
    if summaries:
        curated.set(summaries)


def _event_grid_batch(notification: func.EventHubEvent) -> list[dict[str, Any]]:
    """Parse one delivered message into the list of Event Grid events it carries.

    Event Grid always delivers a JSON array - "an array with a single event" by default, longer
    only when batching is enabled on the subscription.
    https://learn.microsoft.com/en-us/azure/event-grid/delivery-and-retry
    """
    body = notification.get_body().decode("utf-8")
    try:
        parsed = json.loads(body)
    except ValueError:
        logging.warning("NOTIFICATION_NOT_JSON body=%s", body[:200])
        return []
    if isinstance(parsed, dict):
        # Tolerated so the function still works if a producer hand-posts a single event.
        return [parsed]
    return parsed


def _read_archive(file_url: str) -> list[dict[str, Any]]:
    """Download a Capture archive and decode its Avro records into telemetry dicts."""
    import io

    import fastavro
    from azure.storage.blob import BlobServiceClient

    connection_string = os.environ["STORAGE_CONNECTION_STRING"]
    container, blob_name = _split_blob_url(file_url)

    service = BlobServiceClient.from_connection_string(connection_string)
    payload = service.get_container_client(container).download_blob(blob_name).readall()

    readings = []
    for record in fastavro.reader(io.BytesIO(payload)):
        body = record.get("Body")
        if not body:
            continue
        try:
            readings.append(json.loads(bytes(body).decode("utf-8")))
        except ValueError:
            continue
    return readings


def _split_blob_url(file_url: str) -> tuple[str, str]:
    """Split a Capture fileUrl into (container, blob name).

    The URL is whatever the service put in the event, so the path is taken apart rather than
    rebuilt from configuration - the container name is not assumed to be the one we deployed.
    """
    path = unquote(urlparse(file_url).path).lstrip("/")
    container, _, blob_name = path.partition("/")
    return container, blob_name


def _summarize(
    readings: list[dict[str, Any]], capture_data: dict[str, Any], subject: str
) -> list[dict[str, Any]]:
    """Aggregate one archive's readings into a summary per device."""
    by_device: dict[str, list[dict[str, Any]]] = {}
    for reading in readings:
        device_id = reading.get("device_id")
        if device_id:
            by_device.setdefault(device_id, []).append(reading)

    summaries = []
    for device_id, device_readings in sorted(by_device.items()):
        temperatures = [
            float(reading["temperature"])
            for reading in device_readings
            if reading.get("temperature") is not None
        ]
        if not temperatures:
            continue
        excursions = [value for value in temperatures if value >= TEMPERATURE_LIMIT]
        summaries.append(
            {
                "device_id": device_id,
                "source_hub": subject,
                "partition_id": capture_data.get("partitionId"),
                "archive_url": capture_data.get("fileUrl"),
                # The archive's own sequence range: a downstream consumer can use it to detect a
                # gap between windows without re-reading the hub.
                "first_sequence_number": capture_data.get("firstSequenceNumber"),
                "last_sequence_number": capture_data.get("lastSequenceNumber"),
                "reading_count": len(temperatures),
                "min_temperature": round(min(temperatures), 2),
                "max_temperature": round(max(temperatures), 2),
                "mean_temperature": round(sum(temperatures) / len(temperatures), 2),
                "excursion_count": len(excursions),
                "temperature_limit": TEMPERATURE_LIMIT,
                "summarized_at": datetime.now(UTC).isoformat(),
            }
        )
        logging.info(
            "DEVICE_SUMMARY device=%s readings=%d max=%.2f excursions=%d",
            device_id,
            len(temperatures),
            max(temperatures),
            len(excursions),
        )
    return summaries
