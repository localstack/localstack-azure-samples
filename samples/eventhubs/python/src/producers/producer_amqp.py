"""POS terminals: publish payments over AMQP 1.0 with the official Event Hubs SDK.

This is the mainstream Azure path - `azure-eventhub` speaks AMQP 1.0 to the namespace.
Two properties worth watching in the sample:

* **Partition keys**: every event is keyed on the account id, so all transactions for one
  account always land on the same partition and are therefore processed in order. That is
  what makes per-account velocity rules (see the fraud detector) correct.
* **Batching**: events are added to an `EventDataBatch`, which the SDK sends as a single
  AMQP transfer. Batches are how you get throughput without giving up per-account ordering.

Usage:
    python producer_amqp.py [--count 40] [--burst-account ACC-0007]
"""

import argparse

from azure.eventhub import EventData, EventHubProducerClient
from common import (
    connection_string,
    encode_payment,
    event_hub_name,
    make_payment,
    progress,
    summarize,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish payment events over AMQP 1.0.")
    parser.add_argument("--count", type=int, default=40, help="number of payments to publish")
    parser.add_argument(
        "--burst-account",
        default=None,
        help="also emit a rapid burst of small payments for this account, which trips the "
        "velocity rule in the fraud detector",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    conn_str = connection_string()
    hub = event_hub_name()

    payments = [make_payment() for _ in range(args.count)]
    if args.burst_account:
        # A burst of low-value transactions on one account in quick succession: individually
        # unremarkable, collectively the classic card-testing pattern.
        payments += [
            make_payment(account_id=args.burst_account, amount=round(3.0 + index, 2))
            for index in range(12)
        ]

    producer = EventHubProducerClient.from_connection_string(conn_str, eventhub_name=hub)
    progress(f"connected to '{hub}' over AMQP")

    sent = 0
    with producer:
        # One batch per account key: the partition key travels with the batch, so every
        # event inside it is routed to the same partition.
        by_account: dict[str, list[dict]] = {}
        for payment in payments:
            by_account.setdefault(payment["account_id"], []).append(payment)

        for account_id, account_payments in by_account.items():
            batch = producer.create_batch(partition_key=account_id)
            for payment in account_payments:
                event = EventData(encode_payment(payment))
                event.properties = {
                    "source": "pos-terminal",
                    "protocol": "amqp",
                    "account_id": account_id,
                }
                try:
                    batch.add(event)
                except ValueError:
                    # Batch is full - send it and start a new one for the same key.
                    producer.send_batch(batch)
                    sent += len(batch)
                    batch = producer.create_batch(partition_key=account_id)
                    batch.add(event)
            producer.send_batch(batch)
            sent += len(batch)

    progress(f"AMQP producer sent {sent} events: {summarize(payments)}")


if __name__ == "__main__":
    main()
