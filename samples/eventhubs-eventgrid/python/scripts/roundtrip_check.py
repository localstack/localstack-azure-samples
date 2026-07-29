"""Data-plane checks used by validate.sh.

Two modes:

* default   - publish a uniquely marked event with the send-only rule and read it back
              with the listen-only rule, proving both credentials and the round trip.
* --partitions - read runtime metadata for every partition, proving the management
              endpoint of the data plane answers.

Prints a single line starting with ROUNDTRIP_OK / PARTITIONS_OK on success so the shell
script can branch on it.
"""

import os
import sys
import threading
from uuid import uuid4

from azure.eventhub import EventData, EventHubConsumerClient, EventHubProducerClient

EVENT_HUB_NAME = os.environ.get("EVENT_HUB_NAME", "payments")
RECEIVE_TIMEOUT_SECONDS = 45


def partitions_check() -> int:
    conn = os.environ.get("EVENTHUB_LISTEN_CONNECTION_STRING") or os.environ.get(
        "EVENTHUB_SEND_CONNECTION_STRING", ""
    )
    if not conn:
        print("no connection string available")
        return 1
    client = EventHubProducerClient.from_connection_string(conn, eventhub_name=EVENT_HUB_NAME)
    with client:
        partition_ids = client.get_partition_ids()
        total = 0
        for partition_id in partition_ids:
            properties = client.get_partition_properties(partition_id)
            total += properties["last_enqueued_sequence_number"] + 1
    if "--total" in sys.argv:
        print(total)
    else:
        print(f"PARTITIONS_OK {len(partition_ids)} partitions, {total} events so far")
    return 0


def roundtrip_check() -> int:
    send_conn = os.environ.get("EVENTHUB_SEND_CONNECTION_STRING", "")
    listen_conn = os.environ.get("EVENTHUB_LISTEN_CONNECTION_STRING", "")
    if not send_conn or not listen_conn:
        print("send and listen connection strings are both required")
        return 1

    marker = f"validate-{uuid4().hex}"
    partition_key = "VALIDATION"

    producer = EventHubProducerClient.from_connection_string(send_conn, eventhub_name=EVENT_HUB_NAME)
    with producer:
        batch = producer.create_batch(partition_key=partition_key)
        batch.add(EventData(marker))
        producer.send_batch(batch)

    found = threading.Event()
    consumer = EventHubConsumerClient.from_connection_string(
        listen_conn, consumer_group="$Default", eventhub_name=EVENT_HUB_NAME
    )

    def on_event(context, event):
        if event is not None and event.body_as_str() == marker:
            found.set()

    def receive() -> None:
        # starting_position "-1" means "from the beginning of the partition".
        with consumer:
            consumer.receive(on_event=on_event, starting_position="-1", max_wait_time=5)

    receiver = threading.Thread(target=receive, daemon=True)
    receiver.start()
    found.wait(timeout=RECEIVE_TIMEOUT_SECONDS)
    try:
        consumer.close()
    except Exception:
        pass
    receiver.join(timeout=10)

    if found.is_set():
        print(f"ROUNDTRIP_OK sent and received {marker[:18]}...")
        return 0
    print(f"event {marker} was not received within {RECEIVE_TIMEOUT_SECONDS}s")
    return 1


if __name__ == "__main__":
    if "--partitions" in sys.argv or "--total" in sys.argv:
        raise SystemExit(partitions_check())
    raise SystemExit(roundtrip_check())
