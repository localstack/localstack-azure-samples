"""Shared configuration and helpers for the payment-stream producers.

Every producer reads its Event Hubs connection string from the environment, exactly as a
real workload would (the deploy script stores them in Key Vault and exports them here).
Nothing in this module is LocalStack-specific: the same code runs unchanged against Azure.
"""

import json
import os
import random
import time
import uuid
from datetime import UTC, datetime
from urllib.parse import urlparse

# The Avro contract published to the Schema Registry. Producers serialize against it so
# every consumer - Python, Java, .NET or a Kafka client - can decode the stream.
PAYMENT_SCHEMA = {
    "type": "record",
    "name": "PaymentEvent",
    "namespace": "com.contoso.payments",
    "fields": [
        {"name": "transaction_id", "type": "string"},
        {"name": "account_id", "type": "string"},
        {"name": "merchant", "type": "string"},
        {"name": "country", "type": "string"},
        {"name": "amount", "type": "double"},
        {"name": "currency", "type": "string"},
        {"name": "channel", "type": "string"},
        {"name": "timestamp", "type": "string"},
    ],
}

MERCHANTS = [
    "contoso-grocery",
    "fabrikam-electronics",
    "northwind-travel",
    "adventure-works",
    "tailwind-fuel",
]
COUNTRIES = ["GB", "DE", "FR", "US", "NL"]
ACCOUNTS = [f"ACC-{index:04d}" for index in range(1, 21)]

# Transactions above this amount, or a burst of transactions from one account, are what the
# fraud detector looks for. The generator deliberately produces a few of each.
SUSPICIOUS_AMOUNT = 5000.0


def require_env(name: str) -> str:
    """Return an environment variable or fail loudly with a hint on how to set it."""
    value = os.environ.get(name)
    if not value:
        raise SystemExit(
            f"Environment variable {name} is not set. "
            f"Run 'source scripts/export-connection-info.sh' (or scripts/deploy.sh) first."
        )
    return value


def event_hub_name() -> str:
    return os.environ.get("EVENT_HUB_NAME", "payments")


def connection_string() -> str:
    return require_env("EVENTHUB_SEND_CONNECTION_STRING")


def namespace_endpoint(conn_str: str) -> str:
    """Extract 'host:port' from the Endpoint of a connection string.

    Kafka clients bootstrap to a fixed address and, unlike AMQP, have no connection string
    to carry it. The Event Hubs namespace endpoint serves both protocols, so deriving the
    bootstrap server from the connection string keeps the producer portable across
    LocalStack and Azure without hardcoding a host or port.
    """
    endpoint = ""
    for part in conn_str.split(";"):
        if part.startswith("Endpoint="):
            endpoint = part.split("=", 1)[1]
            break
    parsed = urlparse(endpoint)
    host = parsed.hostname or "localhost"
    port = parsed.port or (9093 if "servicebus.windows.net" not in host else 9093)
    return f"{host}:{port}"


def namespace_netloc(conn_str: str) -> str:
    """Return 'host' or 'host:port' for the namespace, as addressed over HTTPS.

    Azure endpoints carry no explicit port (443 is implied); the emulator embeds its own
    port in the connection string. Keeping the port when present - and omitting it when not
    - lets the HTTP producer and the Schema Registry client address either target with the
    same code.
    """
    endpoint = ""
    for part in conn_str.split(";"):
        if part.startswith("Endpoint="):
            endpoint = part.split("=", 1)[1]
            break
    parsed = urlparse(endpoint)
    host = parsed.hostname or ""
    return f"{host}:{parsed.port}" if parsed.port and parsed.port not in (80, 443) else host


def http_netloc(conn_str: str) -> str:
    """Return the 'host[:port]' that serves the Event Hubs HTTP runtime API.

    On Azure the REST API and AMQP share the namespace FQDN on their default ports, so the
    host alone is enough. LocalStack serves AMQP on a dedicated port (embedded in the
    connection string) while the REST API is served by the emulator gateway, so the local
    branch swaps in the gateway port. `EVENTHUB_HTTP_ENDPOINT` overrides both.
    """
    override = os.environ.get("EVENTHUB_HTTP_ENDPOINT")
    if override:
        return override.replace("https://", "").replace("http://", "").rstrip("/")
    netloc = namespace_netloc(conn_str)
    host = netloc.split(":")[0]
    if host.endswith("localhost.localstack.cloud"):
        return f"{host}:{os.environ.get('LOCALSTACK_GATEWAY_PORT', '4566')}"
    return host


def sas_credentials(conn_str: str) -> tuple[str, str, str]:
    """Return (http_netloc, shared_access_key_name, shared_access_key).

    The netloc is the one the HTTP request is sent to, and the SAS token is signed over the
    same value, which is what Azure expects.
    """
    parts = dict(item.split("=", 1) for item in conn_str.split(";") if "=" in item)
    return http_netloc(conn_str), parts.get("SharedAccessKeyName", ""), parts.get("SharedAccessKey", "")


def make_payment(
    *,
    account_id: str | None = None,
    amount: float | None = None,
    channel: str = "pos-terminal",
) -> dict:
    """Build one payment event. Roughly 1 in 12 is deliberately suspicious."""
    if amount is None:
        if random.randint(1, 12) == 1:
            amount = round(random.uniform(SUSPICIOUS_AMOUNT, SUSPICIOUS_AMOUNT * 4), 2)
        else:
            amount = round(random.uniform(5.0, 400.0), 2)
    return {
        "transaction_id": str(uuid.uuid4()),
        "account_id": account_id or random.choice(ACCOUNTS),
        "merchant": random.choice(MERCHANTS),
        "country": random.choice(COUNTRIES),
        "amount": amount,
        "currency": "EUR",
        "channel": channel,
        "timestamp": datetime.now(UTC).isoformat(),
    }


def encode_payment(payment: dict) -> bytes:
    """Serialize a payment as JSON.

    The Avro *contract* lives in the Schema Registry (see schema_register.py) and is what
    consumers validate against; the payload itself stays JSON so the sample stays readable
    in the dashboard and in captured archives. Switching to Avro binary is a one-line
    change with fastavro's schemaless_writer.
    """
    return json.dumps(payment).encode("utf-8")


def summarize(payments: list[dict]) -> str:
    total = sum(payment["amount"] for payment in payments)
    suspicious = sum(1 for payment in payments if payment["amount"] >= SUSPICIOUS_AMOUNT)
    return f"{len(payments)} payments, total EUR {total:,.2f}, {suspicious} above the fraud threshold"


def progress(message: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)
