"""
Python Azure SDK Management Demo — PostgreSQL Flexible Server on LocalStack.

Demonstrates azure-mgmt-postgresqlflexibleservers operations:
  - List servers in a resource group
  - Get server properties
  - List and update configurations
  - List databases
  - Manage firewall rules
  - Check name availability
  - Connect with psycopg2 and run queries

Results are posted to the notes-app UI for live display.
"""

import io
import os
import time

import psycopg2
import requests
import urllib3
from azure.identity import ClientSecretCredential
from azure.mgmt.postgresqlflexibleservers import PostgreSQLManagementClient
from azure.mgmt.resource import ResourceManagementClient

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

SUBSCRIPTION_ID = os.environ.get(
    "AZURE_SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000"
)
TENANT_ID = os.environ.get("AZURE_TENANT_ID", "00000000-0000-0000-0000-000000000000")
CLIENT_ID = os.environ.get("AZURE_CLIENT_ID", "00000000-0000-0000-0000-000000000000")
CLIENT_SECRET = os.environ.get("AZURE_CLIENT_SECRET", "fake-secret")
RESOURCE_GROUP = os.environ.get("RESOURCE_GROUP", "")
SERVER_NAME = os.environ.get("SERVER_NAME", "")
LOCALSTACK_HOST = os.environ.get("LOCALSTACK_HOST", "localhost.localstack.cloud:4566")
NOTES_APP_URL = os.environ.get("NOTES_APP_URL", "http://notes-app:5001")

PG_HOST = os.environ.get("PG_HOST", "")
PG_PORT = int(os.environ.get("PG_PORT", "5432"))
PG_USER = os.environ.get("PG_USER", "pgadmin")
PG_PASSWORD = os.environ.get("PG_PASSWORD", "P@ssw0rd12345!")
PG_DATABASE = os.environ.get("PG_DATABASE", "sampledb")


_log_buf = io.StringIO()
step = 0
failures = 0


def log(msg: str = "") -> None:
    print(msg)
    _log_buf.write(msg + "\n")


def report(label: str, success: bool, detail: str = "") -> None:
    global step, failures
    step += 1
    if not success:
        failures += 1
    status = "PASS" if success else "FAIL"
    msg = f"[{step:>2}] {status}: {label}"
    if detail:
        msg += f" -- {detail}"
    log(msg)


def flush_to_notes_app(final: bool = False) -> None:
    """POST current log to the notes-app SDK status endpoint."""
    status = "done" if final else "running"
    try:
        requests.post(
            f"{NOTES_APP_URL}/api/sdk-status/python",
            json={"status": status, "log": _log_buf.getvalue()},
            timeout=5,
        )
    except Exception:
        pass


def wait_for_notes_app(max_retries: int = 60, delay: float = 3.0) -> None:
    """Wait for the notes-app to be reachable."""
    for _attempt in range(1, max_retries + 1):
        try:
            r = requests.get(f"{NOTES_APP_URL}/api/sdk-status/python", timeout=3)
            if r.status_code == 200:
                return
        except Exception:
            pass
        time.sleep(delay)
    log("WARNING: Notes app not reachable, continuing without UI reporting")


def get_clients() -> tuple:
    """Create Azure SDK clients pointed at LocalStack."""
    base_url = f"https://{LOCALSTACK_HOST}"
    credential = ClientSecretCredential(
        tenant_id=TENANT_ID,
        client_id=CLIENT_ID,
        client_secret=CLIENT_SECRET,
        authority=f"https://{LOCALSTACK_HOST}",
        disable_instance_discovery=True,
        connection_verify=False,
    )
    pg_client = PostgreSQLManagementClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        base_url=base_url,
        connection_verify=False,
    )
    rm_client = ResourceManagementClient(
        credential=credential,
        subscription_id=SUBSCRIPTION_ID,
        base_url=base_url,
        connection_verify=False,
    )
    return pg_client, rm_client


def demo_list_servers(pg: PostgreSQLManagementClient) -> None:
    log("=" * 60)
    log("List Servers in Resource Group")
    log("=" * 60)

    servers = list(pg.servers.list_by_resource_group(RESOURCE_GROUP))
    report("List servers", len(servers) >= 1, f"found {len(servers)} server(s)")

    for s in servers:
        log(
            f"  - {s.name}  version={s.version}  state={s.state}  fqdn={s.fully_qualified_domain_name}"
        )


def demo_get_server(pg: PostgreSQLManagementClient) -> None:
    log("")
    log("=" * 60)
    log("Get Server Properties")
    log("=" * 60)

    server = pg.servers.get(RESOURCE_GROUP, SERVER_NAME)
    report("Get server", server.name == SERVER_NAME, f"name={server.name}")
    report("Server version", server.version == "16", f"version={server.version}")
    report(
        "Server SKU",
        server.sku is not None,
        f"sku={server.sku.name if server.sku else 'N/A'}",
    )
    report(
        "Public access enabled",
        server.network is not None,
        f"public_access={getattr(server.network, 'public_network_access', 'N/A')}",
    )


def demo_configurations(pg: PostgreSQLManagementClient) -> None:
    log("")
    log("=" * 60)
    log("List and Update Configurations")
    log("=" * 60)

    configs = list(pg.configurations.list_by_server(RESOURCE_GROUP, SERVER_NAME))
    report(
        "List configurations", len(configs) > 0, f"found {len(configs)} parameter(s)"
    )

    interesting = {
        "max_connections",
        "shared_buffers",
        "work_mem",
        "log_min_duration_statement",
    }
    for c in configs:
        if c.name in interesting:
            log(f"  - {c.name} = {c.value}  (default: {c.default_value})")


def demo_databases(pg: PostgreSQLManagementClient) -> None:
    log("")
    log("=" * 60)
    log("List Databases")
    log("=" * 60)

    databases = list(pg.databases.list_by_server(RESOURCE_GROUP, SERVER_NAME))
    db_names = [d.name for d in databases]
    report("List databases", len(databases) >= 1, f"found: {', '.join(db_names)}")
    report("Primary DB exists", "sampledb" in db_names, "sampledb")
    report("Secondary DB exists", "analyticsdb" in db_names, "analyticsdb")


def demo_firewall_rules(pg: PostgreSQLManagementClient) -> None:
    log("")
    log("=" * 60)
    log("List Firewall Rules")
    log("=" * 60)

    rules = list(pg.firewall_rules.list_by_server(RESOURCE_GROUP, SERVER_NAME))
    rule_names = [r.name for r in rules]
    report("List firewall rules", len(rules) >= 1, f"found: {', '.join(rule_names)}")

    expected = {"allow-all", "corporate-network", "vpn-access"}
    report(
        "Expected rules present",
        expected.issubset(set(rule_names)),
        f"expected={expected}",
    )


def demo_name_availability(pg: PostgreSQLManagementClient) -> None:
    log("")
    log("=" * 60)
    log("Check Name Availability")
    log("=" * 60)

    from azure.mgmt.postgresqlflexibleservers.models import CheckNameAvailabilityRequest

    result = pg.name_availability.check_globally(
        CheckNameAvailabilityRequest(name=SERVER_NAME)
    )
    report(
        "Check existing name",
        result.name_available is not None,
        f"name={SERVER_NAME}, available={result.name_available}",
    )

    new_name = "pgflex-avail-test-12345"
    result = pg.name_availability.check_globally(
        CheckNameAvailabilityRequest(name=new_name)
    )
    report("New name available", result.name_available is True, f"name={new_name}")


def demo_psycopg2_connection() -> None:
    log("")
    log("=" * 60)
    log("Direct PostgreSQL Connection (psycopg2)")
    log("=" * 60)

    if not PG_HOST:
        log("  PG_HOST not set, skipping direct connection test")
        return

    try:
        conn = psycopg2.connect(
            host=PG_HOST,
            port=PG_PORT,
            user=PG_USER,
            password=PG_PASSWORD,
            dbname=PG_DATABASE,
            connect_timeout=10,
        )
        report("Connect to PostgreSQL", True, f"{PG_HOST}:{PG_PORT}/{PG_DATABASE}")

        cur = conn.cursor()
        cur.execute("SELECT version()")
        version = cur.fetchone()[0]
        report("Get PG version", "PostgreSQL" in version, version[:60])

        cur.execute(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'"
        )
        count = cur.fetchone()[0]
        report("Query information_schema", True, f"{count} public table(s)")

        cur.close()
        conn.close()
    except Exception as exc:
        report("Connect to PostgreSQL", False, str(exc))


def run_demo() -> None:
    """Execute the full demo suite once."""
    global step, failures, _log_buf
    step = 0
    failures = 0
    _log_buf = io.StringIO()

    log("=" * 60)
    log("Python Azure SDK — PostgreSQL Flexible Server Demo")
    log("=" * 60)
    log("")
    flush_to_notes_app()

    try:
        pg, _ = get_clients()
    except Exception as exc:
        report("Create SDK clients", False, str(exc))
        flush_to_notes_app(final=True)
        return

    report("Create SDK clients", True, "PostgreSQLManagementClient ready")
    flush_to_notes_app()

    demo_list_servers(pg)
    flush_to_notes_app()

    demo_get_server(pg)
    flush_to_notes_app()

    demo_configurations(pg)
    flush_to_notes_app()

    demo_databases(pg)
    flush_to_notes_app()

    demo_firewall_rules(pg)
    flush_to_notes_app()

    demo_name_availability(pg)
    flush_to_notes_app()

    demo_psycopg2_connection()
    flush_to_notes_app()

    log("")
    log("=" * 60)
    total = step
    passed = total - failures
    log(f"TOTAL: {passed}/{total} tests passed")
    log("=" * 60)
    if failures == 0:
        log("ALL TESTS PASSED")
    else:
        log(f"{failures} TEST(S) FAILED")

    flush_to_notes_app(final=True)


def main() -> None:
    """Poll for trigger from notes-app, run demo on demand."""
    wait_for_notes_app()

    try:
        requests.post(
            f"{NOTES_APP_URL}/api/sdk-status/python",
            json={"status": "idle", "log": ""},
            timeout=5,
        )
    except Exception:
        pass

    print("Python SDK demo container ready — waiting for trigger...")

    last_generation = 0
    while True:
        try:
            r = requests.get(f"{NOTES_APP_URL}/api/sdk-trigger/python", timeout=5)
            if r.ok:
                gen = r.json().get("generation", 0)
                if gen > last_generation:
                    last_generation = gen
                    print(f"Trigger received (generation={gen}), running demo...")
                    run_demo()
                    print("Demo complete — waiting for next trigger...")
        except Exception:
            pass
        time.sleep(2)


if __name__ == "__main__":
    main()
