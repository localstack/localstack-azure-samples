"""Publish the payment Avro contract to the Event Hubs Schema Registry.

Schema Registry is the governance half of a streaming platform: producers and consumers
agree on a versioned contract instead of on tribal knowledge. This script registers the
schema, then reads it back by id - the same two calls a serializer makes at runtime.

The Schema Registry data plane lives on the namespace host alongside AMQP and Kafka, and
is addressed with a bearer token, so this uses `requests` plus `azure-identity`. Usage:

    python schema_register.py [--show]
"""

import argparse
import json
import os

import requests
from azure.identity import ClientSecretCredential, DefaultAzureCredential
from common import PAYMENT_SCHEMA, connection_string, progress, sas_credentials

API_VERSION = "2023-07-01"
SCHEMA_GROUP = os.environ.get("SCHEMA_GROUP_NAME", "payments-schemas")
SCHEMA_NAME = "PaymentEvent"


def get_token() -> str:
    """Acquire a data-plane token for the Event Hubs scope."""
    # Against LocalStack any service principal is accepted; against Azure these come from
    # the environment exactly as they would for any workload identity.
    tenant_id = os.environ.get("AZURE_TENANT_ID")
    client_id = os.environ.get("AZURE_CLIENT_ID")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")
    if tenant_id and client_id and client_secret:
        credential = ClientSecretCredential(tenant_id, client_id, client_secret)
    else:
        credential = DefaultAzureCredential()
    return credential.get_token("https://eventhubs.azure.net/.default").token


def registry_base() -> str:
    host, _, _ = sas_credentials(connection_string())
    return f"https://{host}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Register the payment Avro schema.")
    parser.add_argument("--show", action="store_true", help="list registered schemas and exit")
    args = parser.parse_args()

    base = registry_base()
    session = requests.Session()
    # Only the emulator's certificate is self-signed; against real Azure this stays on.
    session.verify = "localhost.localstack.cloud" not in base
    session.headers["Authorization"] = f"Bearer {get_token()}"

    if args.show:
        response = session.get(f"{base}/$schemaGroups?api-version={API_VERSION}", timeout=30)
        response.raise_for_status()
        progress(f"schema groups: {json.dumps(response.json().get('Value', []))}")
        # Listing a group's schemas is not part of the data plane; the spec exposes the
        # versions of a named schema, so ask about the contract this script registers.
        response = session.get(
            f"{base}/$schemaGroups/{SCHEMA_GROUP}/schemas/{SCHEMA_NAME}/versions"
            f"?api-version={API_VERSION}",
            timeout=30,
        )
        if response.ok:
            versions = response.json().get("Value", [])
            progress(f"'{SCHEMA_NAME}' in '{SCHEMA_GROUP}': versions {json.dumps(versions)}")
        return

    # Register (or re-register - the call is idempotent and returns the existing id when the
    # content is unchanged, which is what makes it safe to run on every deployment).
    url = (
        f"{base}/$schemaGroups/{SCHEMA_GROUP}/schemas/{SCHEMA_NAME}"
        f"?api-version={API_VERSION}"
    )
    response = session.put(
        url,
        data=json.dumps(PAYMENT_SCHEMA),
        headers={"Content-Type": "application/json; serialization=Avro"},
        timeout=30,
    )
    if not response.ok:
        raise SystemExit(f"schema registration failed: {response.status_code} {response.text[:300]}")

    schema_id = response.headers.get("Schema-Id", "<unknown>")
    version = response.headers.get("Schema-Version", "<unknown>")
    progress(f"registered '{SCHEMA_NAME}' in group '{SCHEMA_GROUP}' -> id={schema_id} version={version}")

    # Read it back by id, the way a deserializer resolves an unknown schema id at runtime.
    lookup = session.get(f"{base}/$schemaGroups/$schemas/{schema_id}?api-version={API_VERSION}", timeout=30)
    if lookup.ok:
        fields = [field["name"] for field in json.loads(lookup.text)["fields"]]
        progress(f"resolved schema id {schema_id} -> fields: {', '.join(fields)}")
    else:
        progress(f"WARNING: could not resolve schema id {schema_id}: {lookup.status_code}")


if __name__ == "__main__":
    import urllib3

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    main()
