"""Fraud detection: an Event Hubs-triggered Function App.

This is the hot path of the pipeline. The Functions host owns the hard parts of stream
processing so the sample does not have to: it leases partitions across instances, tracks
checkpoints in Blob Storage, and redelivers from the last checkpoint after a restart. The
code below only has to answer one question per event - is this payment suspicious?

Bindings
--------
* trigger: `payments` event hub, consumer group `fraud-detector`, cardinality MANY so the
  host delivers a batch per invocation (the throughput setting that matters most) - which
  is why the parameter is a list.
* output: `fraud-alerts` event hub - the alerts stream other systems subscribe to.

Two binding rules the Python worker enforces, both of which fail the function *load* rather
than an invocation, so they are easy to miss:

* the batch parameter must be annotated ``List[func.EventHubEvent]`` from ``typing`` - the
  builtin ``list[...]`` generic is rejected as an "invalid non-type annotation";
* the output must be ``func.Out[List[str]]`` to emit several events from one invocation;
  with ``func.Out[str]`` a list assignment is dropped and no alerts are published;
* event bodies must be JSON, because the host deserializes them before binding.

Detection rules
---------------
1. **Amount**: a single payment at or above the threshold.
2. **Velocity**: more than N payments for one account inside a short window - the
   card-testing pattern. Ordering per account is guaranteed because producers key events
   on the account id, so all of an account's payments land on one partition and one
   instance sees them in order.

The velocity window lives in memory per instance, which is exactly what per-partition
ownership makes safe. State that must outlive a restart belongs in a store (Cosmos DB,
Table Storage); the checkpoint itself is handled by the host.
"""

import json
import logging
import os
from collections import defaultdict, deque
from datetime import UTC, datetime
from typing import List

import azure.functions as func

logging.basicConfig(level=logging.INFO)

app = func.FunctionApp()

SUSPICIOUS_AMOUNT = float(os.environ.get("FRAUD_AMOUNT_THRESHOLD", "5000"))
VELOCITY_COUNT = int(os.environ.get("FRAUD_VELOCITY_COUNT", "5"))
VELOCITY_WINDOW_SECONDS = int(os.environ.get("FRAUD_VELOCITY_WINDOW_SECONDS", "60"))

# account id -> recent payment timestamps, for the velocity rule
_recent_by_account: dict[str, deque] = defaultdict(lambda: deque(maxlen=50))


def _parse_timestamp(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return datetime.now(UTC)


def evaluate(payment: dict) -> list[str]:
    """Return the list of rules a payment trips (empty means it looks legitimate)."""
    reasons: list[str] = []

    amount = float(payment.get("amount", 0))
    if amount >= SUSPICIOUS_AMOUNT:
        reasons.append(f"amount {amount:.2f} >= threshold {SUSPICIOUS_AMOUNT:.2f}")

    account_id = payment.get("account_id", "unknown")
    now = _parse_timestamp(payment.get("timestamp", ""))
    recent = _recent_by_account[account_id]
    recent.append(now)
    within_window = [
        seen for seen in recent if (now - seen).total_seconds() <= VELOCITY_WINDOW_SECONDS
    ]
    if len(within_window) > VELOCITY_COUNT:
        reasons.append(
            f"velocity {len(within_window)} payments in {VELOCITY_WINDOW_SECONDS}s "
            f"(limit {VELOCITY_COUNT})"
        )

    return reasons


@app.function_name(name="FraudDetector")
@app.event_hub_message_trigger(
    arg_name="events",
    event_hub_name="%EVENT_HUB_NAME%",
    connection="EVENTHUB_LISTEN_CONNECTION",
    consumer_group="%FRAUD_CONSUMER_GROUP%",
    cardinality=func.Cardinality.MANY,
)
@app.event_hub_output(
    arg_name="alerts",
    event_hub_name="%ALERT_HUB_NAME%",
    connection="EVENTHUB_SEND_CONNECTION",
)
def FraudDetector(events: List[func.EventHubEvent], alerts: func.Out[List[str]]) -> None:
    processed = 0
    flagged: list[str] = []

    for event in events:
        processed += 1
        try:
            payment = json.loads(event.get_body().decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            # A payload that is not our contract: log and move on rather than failing the
            # whole batch, which would redeliver the good events too.
            logging.warning("skipping event with an undecodable body")
            continue

        # System properties tell us which partition the event came from, which is how you
        # prove per-account ordering in a demo (and debug skew in production).
        partition = (event.metadata or {}).get("PartitionContext", {}).get("PartitionId")

        reasons = evaluate(payment)
        if reasons:
            alert = {
                "alert_id": f"ALERT-{payment.get('transaction_id', '')[:8]}",
                "transaction_id": payment.get("transaction_id"),
                "account_id": payment.get("account_id"),
                "merchant": payment.get("merchant"),
                "amount": payment.get("amount"),
                "currency": payment.get("currency"),
                "channel": payment.get("channel"),
                "partition": partition,
                "reasons": reasons,
                "detected_at": datetime.now(UTC).isoformat(),
            }
            flagged.append(json.dumps(alert))
            logging.warning(
                "FRAUD_ALERT account=%s amount=%s reasons=%s",
                payment.get("account_id"),
                payment.get("amount"),
                "; ".join(reasons),
            )

    if flagged:
        # One output binding call emits the whole batch of alerts.
        alerts.set(flagged)

    logging.info(
        "FRAUD_BATCH processed=%d flagged=%d threshold=%s",
        processed,
        len(flagged),
        SUSPICIOUS_AMOUNT,
    )
