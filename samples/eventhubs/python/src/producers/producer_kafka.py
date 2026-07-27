"""Legacy Kafka application: publishes to the *same* event hub with no Azure SDK at all.

This is the migration story enterprises care about. An existing Kafka producer keeps its
code, its client library (librdkafka via confluent-kafka) and its mental model - only the
bootstrap address and credentials change. The events it writes are indistinguishable from
the AMQP ones downstream: the fraud detector reads them over AMQP, and Capture archives
them, because an event hub is one log with several protocol front-ends.

The bootstrap address is derived from the Event Hubs connection string rather than
hardcoded, so this runs unchanged against LocalStack and against Azure.

Usage:
    python producer_kafka.py [--count 15]
"""

import argparse

from common import (
    connection_string,
    encode_payment,
    event_hub_name,
    make_payment,
    namespace_endpoint,
    progress,
    summarize,
)
from confluent_kafka import Producer


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish payment events with a Kafka client.")
    parser.add_argument("--count", type=int, default=15, help="number of payments to publish")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    conn_str = connection_string()
    hub = event_hub_name()
    bootstrap = namespace_endpoint(conn_str)

    # Topic == event hub. Against Azure you would add
    # security.protocol=SASL_SSL / sasl.mechanism=PLAIN with the connection string as the
    # password; the emulator serves Kafka in plaintext (a documented deviation).
    producer = Producer(
        {
            "bootstrap.servers": bootstrap,
            "client.id": "legacy-settlement-gateway",
            "message.timeout.ms": 20000,
            # Broker metadata advertises a hostname; pinning the client to IPv4 avoids a
            # pointless ::1 connection attempt on dual-stack hosts (the retry succeeds
            # either way, this just keeps the logs clean).
            "broker.address.family": "v4",
        }
    )
    progress(f"connected to '{hub}' over the Kafka protocol at {bootstrap}")

    failures: list[str] = []

    def on_delivery(error, message) -> None:
        if error is not None:
            failures.append(str(error))

    payments = [make_payment(channel="settlement-batch") for _ in range(args.count)]
    for payment in payments:
        producer.produce(
            hub,
            value=encode_payment(payment),
            key=payment["account_id"],  # same keying rule as the AMQP producer
            headers=[("source", b"legacy-gateway"), ("protocol", b"kafka")],
            on_delivery=on_delivery,
        )
    producer.flush(30)

    if failures:
        raise SystemExit(f"Kafka delivery failed: {failures[:3]}")

    progress(f"Kafka producer sent {len(payments)} events: {summarize(payments)}")


if __name__ == "__main__":
    main()
