# Terraform deployment

Provisions the payment fraud detection pipeline with Terraform, then publishes the
application code with the Azure CLI.

## Prerequisites

- The LocalStack Azure emulator is running and `lstk az start-interception` has been run.
- `terraform` and `az` are on the PATH.

The provider is already pointed at the emulator in `providers.tf`
(`metadata_host = "localhost.localstack.cloud:4566"`), so no `tflocal` wrapper is needed.

## Usage

```bash
cd samples/eventhubs/python/terraform
bash deploy.sh
```

`deploy.sh` runs `init`, `validate`, `plan`, `apply`, a second `apply` to prove
idempotency, then zip-deploys the Function App and the Web App and verifies the payments
hub.

To tear down:

```bash
terraform destroy --auto-approve
```

## What it creates

| Resource | Purpose |
|----------|---------|
| `azurerm_resource_group` | Container for everything below |
| `azurerm_storage_account` + `azurerm_storage_container` | Capture archives, checkpoints, function content |
| `azurerm_log_analytics_workspace` + `azurerm_application_insights` | Telemetry for both workloads |
| `azurerm_eventhub_namespace` | Standard tier, Kafka enabled, auto-inflate to 4 TU |
| `azurerm_eventhub.payments` | 4 partitions, Capture to Avro on a 60s window |
| `azurerm_eventhub.alerts` | 2 partitions, carries fraud alerts |
| `azurerm_eventhub_consumer_group` (x3) | `fraud-detector`, `analytics`, `audit` |
| `azurerm_eventhub_authorization_rule` (x3) | Send-only, listen-only, alerts-send |
| `azurerm_eventhub_namespace_schema_group` | Avro contract group, forward compatibility |
| `azurerm_key_vault` + 3 secrets | Connection strings kept out of app settings |
| `azurerm_linux_function_app` | Event Hubs trigger running fraud detection |
| `azurerm_linux_web_app` | Operations dashboard |

## Variables

Every value is a variable with a sensible default (see `variables.tf`). The ones worth
changing first:

| Variable | Default | Notes |
|----------|---------|-------|
| `partition_count` | `4` | Partitions are the unit of parallelism and of ordering |
| `capture_interval_in_seconds` | `60` | Minimum allowed by Azure; the demo waits for a flush |
| `fraud_amount_threshold` | `5000` | A single payment at or above this is flagged |
| `fraud_velocity_count` | `5` | Payments per account per window before flagging |
| `message_retention_days` | `1` | Standard tier allows up to 7 |

## Outputs

`terraform output` exposes the resource names plus the connection strings (marked
sensitive). The producers read them from the environment:

```bash
export EVENTHUB_SEND_CONNECTION_STRING=$(terraform output -raw eventhub_send_connection_string)
export EVENT_HUB_NAME=$(terraform output -raw event_hub_name)
cd ../src/producers && python producer_amqp.py --count 50
```
