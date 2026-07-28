"""Edge/IoT devices: publish payments over plain HTTPS with a hand-built SAS token.

Constrained devices often cannot carry an AMQP stack or an Azure SDK. Event Hubs exposes
an HTTP runtime API for exactly that case: a POST with a SharedAccessSignature header. The
only dependency here is `requests`, and the SAS token is built from the connection string
with the standard HMAC-SHA256 scheme - the same code an embedded gateway would run.

Usage:
    python producer_http.py [--count 8]
"""

import argparse
import base64
import hashlib
import hmac
import time
from urllib.parse import quote

import requests
from common import (
    connection_string,
    encode_payment,
    event_hub_name,
    make_payment,
    progress,
    sas_credentials,
    summarize,
)


def build_sas_token(uri: str, key_name: str, key: str, ttl_seconds: int = 3600) -> str:
    """Standard Event Hubs SAS token (see the Azure REST reference)."""
    expiry = int(time.time()) + ttl_seconds
    encoded_uri = quote(uri, safe="").lower()
    string_to_sign = f"{encoded_uri}\n{expiry}"
    signature = hmac.new(key.encode("utf-8"), string_to_sign.encode("utf-8"), hashlib.sha256).digest()
    encoded_signature = quote(base64.b64encode(signature), safe="")
    return f"SharedAccessSignature sr={encoded_uri}&sig={encoded_signature}&se={expiry}&skn={key_name}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish payment events over the HTTP runtime API.")
    parser.add_argument("--count", type=int, default=8, help="number of payments to publish")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    conn_str = connection_string()
    hub = event_hub_name()
    host, key_name, key = sas_credentials(conn_str)

    # The resource URI a SAS token is scoped to is the entity address.
    resource_uri = f"https://{host}/{hub}"
    token = build_sas_token(resource_uri, key_name, key)
    endpoint = f"{resource_uri}/messages?api-version=2014-01"
    progress(f"posting to {endpoint} as device gateway")

    payments = [make_payment(channel="atm-terminal") for _ in range(args.count)]
    for payment in payments:
        response = requests.post(
            endpoint,
            data=encode_payment(payment),
            headers={
                "Authorization": token,
                "Content-Type": "application/atom+xml;type=entry;charset=utf-8",
                # Custom headers are delivered as user properties on the event.
                "source": "atm-gateway",
                "protocol": "http",
                # BrokerProperties routes the event by partition key on the emulator,
                # mirroring the partition_key the AMQP and Kafka producers use. Note that
                # this header is not part of the documented Event Hubs REST contract, so
                # against real Azure verify the routing or use the "Send partition event"
                # endpoint when placement has to be explicit.
                "BrokerProperties": '{"PartitionKey": "%s"}' % payment["account_id"],
            },
            timeout=30,
            # Only the emulator's certificate is self-signed. Scoping the exception to it
            # means running this against real Azure still validates the certificate.
            verify="localhost.localstack.cloud" not in endpoint,
        )
        if response.status_code not in (200, 201):
            raise SystemExit(f"HTTP send failed: {response.status_code} {response.text[:200]}")

    progress(f"HTTP producer sent {len(payments)} events: {summarize(payments)}")


if __name__ == "__main__":
    import urllib3

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    main()
