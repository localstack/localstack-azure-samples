"""Read the curated hub and print the device summaries the processor produced.

Used by run-pipeline.sh as the end-to-end proof: a summary here means Capture flushed, Event Grid
delivered the notification, and the function decoded the archive.
"""

import json
import os
import sys
import threading

from azure.eventhub import EventHubConsumerClient

RECEIVE_TIMEOUT_SECONDS = int(os.environ.get("CURATED_RECEIVE_TIMEOUT", "45"))


def main() -> int:
    connection_string = os.environ.get("EVENTHUB_LISTEN_CONNECTION_STRING", "")
    hub_name = os.environ.get("CURATED_HUB_NAME", "curated")
    if not connection_string:
        print("EVENTHUB_LISTEN_CONNECTION_STRING is not set")
        return 1

    summaries: list[dict] = []
    found = threading.Event()

    def on_event(context, event):
        if event is None:
            return
        try:
            summaries.append(json.loads(event.body_as_str()))
        except ValueError:
            return
        found.set()

    consumer = EventHubConsumerClient.from_connection_string(
        connection_string, consumer_group="$Default", eventhub_name=hub_name
    )

    def receive() -> None:
        with consumer:
            consumer.receive(on_event=on_event, starting_position="-1", max_wait_time=5)

    receiver = threading.Thread(target=receive, daemon=True)
    receiver.start()
    found.wait(timeout=RECEIVE_TIMEOUT_SECONDS)
    # Give slightly longer for the remaining partitions once the first summary arrives.
    if found.is_set():
        threading.Event().wait(5)
    try:
        consumer.close()
    except Exception:
        pass
    receiver.join(timeout=10)

    if not summaries:
        print("SUMMARIES_NONE")
        return 1

    print(f"SUMMARIES_OK {len(summaries)}")
    for summary in sorted(summaries, key=lambda item: item.get("device_id", "")):
        print(
            f"  {summary.get('device_id')}: {summary.get('reading_count')} readings, "
            f"min {summary.get('min_temperature')} / mean {summary.get('mean_temperature')} / "
            f"max {summary.get('max_temperature')}, excursions {summary.get('excursion_count')}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
