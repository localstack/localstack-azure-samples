# Terraform deployment

Provisions the payment fraud detection pipeline with Terraform, then publishes the
application code with the Azure CLI.

## Prerequisites

- The LocalStack Azure emulator is running and `lstk az start-interception` has been run.
- `terraform` and `az` are on the PATH.

The provider is already pointed at the emulator in `providers.tf`
(`metadata_host = "azure.localhost.localstack.cloud:4566"`), so no `tflocal` wrapper is needed.

## Usage

```bash
cd samples/eventhubs/python/terraform
bash deploy.sh
```

`deploy.sh` resolves the deploying principal, runs `init`, `validate`, `plan`, `apply`, a
second `apply` to prove idempotency, then zip-deploys the Function App and the Web App and
verifies the payments hub. Then run the scripts of the Azure CLI deployment, which work on
this deployment too:

```bash
bash ../scripts/validate.sh
bash ../scripts/run-pipeline.sh
bash ../scripts/query-telemetry.sh
bash ../scripts/query-logs-and-metrics.sh
```

The key vault uses the RBAC permission model, so `azurerm_key_vault_secret`, which writes
through the Key Vault data plane, needs a data-plane role. `deploy.sh` resolves the object
id of the signed-in user or service principal through Microsoft Graph, or from the `oid`
claim of the CLI's access token, and passes it as `deployer_object_id`: the configuration
gives it the Key Vault Secrets Officer role on the vault and waits for the assignment to
propagate before writing the secrets. When the id can't be resolved, the role must already
be assigned.

To tear down:

```bash
terraform destroy --auto-approve
```

## What it creates

Every resource is created by a module under `modules/`, together with its diagnostic
settings, which send its resource logs and platform metrics to the Log Analytics
workspace:

| Module                 | Resources                                                                                                                                                                                                                                                                                                                  |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `log_analytics`        | The Log Analytics workspace, which audits the queries run on it (`LAQueryLogs`)                                                                                                                                                                                                                                            |
| `application_insights` | The workspace-based Application Insights resource both apps send their telemetry to                                                                                                                                                                                                                                        |
| `storage_account`      | Capture archives, checkpoints and function content, the Capture container, and the diagnostic settings of the account and of its blob, queue and table services                                                                                                                                                            |
| `event_hubs`           | Standard namespace with Kafka and auto-inflate to 4 TU; the `payments` hub (4 partitions, Capture to Avro on a 60s window) and the `fraud-alerts` hub (2 partitions); the `fraud-detector`, `analytics` and `audit` consumer groups; send-only, listen-only, alerts-send and dashboard-listen rules; the Avro schema group |
| `key_vault`            | The key vault with the three connection-string secrets, and the deploying principal's Key Vault Secrets Officer role                                                                                                                                                                                                       |
| `app_service_plan`     | The Consumption plan of the Function App and the S1 plan of the Web App                                                                                                                                                                                                                                                    |
| `function_app`         | The Event Hubs-triggered fraud detection, with the OpenTelemetry settings of the Python worker                                                                                                                                                                                                                             |
| `web_app`              | The operations dashboard                                                                                                                                                                                                                                                                                                   |

## Variables

Every value is a variable with a sensible default (see `variables.tf`). The ones worth
changing first:

| Variable                                         | Default        | Notes                                                                                            |
| ------------------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------ |
| `partition_count`                                | `4`            | Partitions are the unit of parallelism and of ordering                                           |
| `capture_interval_in_seconds`                    | `60`           | Minimum allowed by Azure; the demo waits for a flush                                             |
| `fraud_amount_threshold`                         | `5000`         | A single payment at or above this is flagged                                                     |
| `fraud_velocity_count`                           | `5`            | Payments per account per window before flagging                                                  |
| `message_retention_days`                         | `1`            | Standard tier allows up to 7                                                                     |
| `deployer_object_id` / `deployer_principal_type` | empty / `User` | The principal given Key Vault Secrets Officer on the vault; `deploy.sh` passes the signed-in one |

## Outputs

`terraform output` exposes the resource names plus the connection strings (marked
sensitive). The producers read them from the environment:

```bash
export EVENTHUB_SEND_CONNECTION_STRING=$(terraform output -raw eventhub_send_connection_string)
export EVENT_HUB_NAME=$(terraform output -raw event_hub_name)
cd ../src/producers && python producer_amqp.py --count 50
```
