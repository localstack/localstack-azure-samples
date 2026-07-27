"""Decode the newest Event Hubs Capture archive from Blob Storage.

Capture writes Avro object-container files using Azure's `EventData` record schema, so
any Avro reader can consume them - no Event Hubs client required. That is the whole point
of the cold path: the archive outlives the stream's retention window and is readable by
whatever the analytics team already uses.
"""

import io
import json
import os

import fastavro
from azure.storage.blob import BlobServiceClient

CONTAINER = os.environ.get("CAPTURE_CONTAINER_NAME", "payments-archive")
MAX_RECORDS = int(os.environ.get("CAPTURE_MAX_RECORDS", "3"))


def main() -> None:
    connection_string = os.environ.get("STORAGE_CONNECTION_STRING")
    if not connection_string:
        raise SystemExit("STORAGE_CONNECTION_STRING is not set")

    service = BlobServiceClient.from_connection_string(connection_string)
    container = service.get_container_client(CONTAINER)

    blobs = [blob for blob in container.list_blobs() if blob.size > 0]
    if not blobs:
        # Capture writes empty placeholder blobs for windows with no traffic, so "some blobs
        # exist" is not the same as "the stream was archived". Exit non-zero: run-pipeline.sh
        # treats this as a Capture failure rather than a quiet nothing-to-do.
        raise SystemExit(f"no non-empty capture archives in container '{CONTAINER}'")

    blobs.sort(key=lambda blob: blob.last_modified or 0, reverse=True)
    newest = blobs[0]
    print(f"archive: {newest.name} ({newest.size} bytes)")

    payload = container.download_blob(newest.name).readall()
    reader = fastavro.reader(io.BytesIO(payload))
    print(f"avro schema: {reader.writer_schema.get('name')}")

    decoded = 0
    for index, record in enumerate(reader):
        if index >= MAX_RECORDS:
            break
        decoded += 1
        body = record.get("Body")
        if isinstance(body, bytes):
            try:
                body = json.loads(body.decode("utf-8"))
            except ValueError:
                body = body.decode("utf-8", errors="replace")
        print(
            f"  seq={record.get('SequenceNumber')} offset={record.get('Offset')} "
            f"enqueued={record.get('EnqueuedTimeUtc')}"
        )
        print(f"    {json.dumps(body)[:160]}")

    if not decoded:
        raise SystemExit(f"archive '{newest.name}' holds no readable records")


if __name__ == "__main__":
    main()
