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
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import metrics

# The logger of the function
LOGGER_NAME = "function_app"

# With the APPLICATIONINSIGHTS_CONNECTION_STRING app setting, the Azure Monitor OpenTelemetry Distro sends to
# Application Insights the records of this logger (traces), the exceptions it logs, the custom event and the custom
# metric below. The app configures the distro itself, which works on every hosting plan: on the Linux Consumption
# plan the Python worker sent none of them when PYTHON_APPLICATIONINSIGHTS_ENABLE_TELEMETRY asked it to.
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    configure_azure_monitor(logger_name=LOGGER_NAME)

logger = logging.getLogger(LOGGER_NAME)
logger.setLevel(logging.INFO)

# The custom metric: the number of payments the function screened, by outcome (legitimate, flagged)
# (customMetrics table)
payments_screened = metrics.get_meter(LOGGER_NAME).create_counter(
    "payments_screened", unit="{payment}", description="The number of payments the fraud detector screened."
)

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
        logger.warning("PAYMENT_TIMESTAMP_INVALID timestamp=%r: the velocity rule uses the current time", value)
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
# The trigger hands the function the raw bodies (binary): with the host's default binding, which parses each body as
# JSON, one event that is not JSON failed the whole batch before the function could skip it below
@app.event_hub_message_trigger(
    arg_name="events",
    event_hub_name="%EVENT_HUB_NAME%",
    connection="EVENTHUB_LISTEN_CONNECTION",
    consumer_group="%FRAUD_CONSUMER_GROUP%",
    cardinality=func.Cardinality.MANY,
    data_type=func.DataType.BINARY,
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
            logger.warning("skipping event with an undecodable body")
            continue

        # System properties tell us which partition the event came from, which is how you
        # prove per-account ordering in a demo (and debug skew in production).
        partition = (event.metadata or {}).get("PartitionContext", {}).get("PartitionId")

        try:
            reasons = evaluate(payment)
        except (TypeError, ValueError):
            # A payment whose amount is not a number: log it with its stack trace (exceptions table) and move on,
            # for the same reason as an undecodable body.
            logger.exception("PAYMENT_INVALID transaction=%s", payment.get("transaction_id"))
            continue

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
            logger.warning(
                "FRAUD_ALERT account=%s amount=%s reasons=%s",
                payment.get("account_id"),
                payment.get("amount"),
                "; ".join(reasons),
            )
            # A custom event (customEvents table): the worker sends a log record that carries the
            # microsoft.custom_event.name attribute as a custom event named after its value, with the other
            # attributes as its custom dimensions
            logger.info(
                f"FraudDetected: {alert['alert_id']}",
                extra={
                    "microsoft.custom_event.name": "FraudDetected",
                    "payment.account_id": str(payment.get("account_id", "unknown")),
                    "payment.amount": float(payment.get("amount", 0)),
                    "payment.channel": str(payment.get("channel", "unknown")),
                    "fraud.reasons": "; ".join(reasons),
                },
            )
            payments_screened.add(1, {"outcome": "flagged"})
        else:
            payments_screened.add(1, {"outcome": "legitimate"})

    if flagged:
        # One output binding call emits the whole batch of alerts.
        alerts.set(flagged)

    logger.info(
        "FRAUD_BATCH processed=%d flagged=%d threshold=%s",
        processed,
        len(flagged),
        SUSPICIOUS_AMOUNT,
    )
