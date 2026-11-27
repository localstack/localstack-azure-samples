# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning the sample's Azure resources. For details about the sample application, see [Azure Web App with Azure Database for PostgreSQL flexible server](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (1.5+)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [.NET SDK 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0)
- [PostgreSQL client (`psql`)](https://www.postgresql.org/download/)
- [`jq`](https://jqlang.org/)

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The Terraform configuration provisions:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli).
2. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) with two subnets:
   - *app-subnet* (delegated to `Microsoft.Web/serverFarms` for the Web App's VNet integration)
   - *pe-subnet* (hosts the Private Endpoint to the flex server)
3. [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) `privatelink.postgres.database.azure.com`, linked to the VNet.
4. [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) (group `postgresqlServer`).
5. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview).
6. [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): one per subnet.
7. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview), with a diagnostic setting that sends the audit records of the queries run on the workspace to the workspace itself.
8. [Azure Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview): workspace-based, it stores the telemetry of the web app in the Log Analytics workspace.
9. [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview): public-access mode, Burstable `Standard_B1ms`, version 16, 32 GiB, HA disabled. A permissive firewall rule (`AllowAllIPs`, `0.0.0.0–255.255.255.255`) lets the deploy machine reach the server for the post-apply psql bootstrap.
10. [PostgreSQL database](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-servers) `PlannerDB`.
11. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
12. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with regional VNet integration. Terraform writes `PG_HOST`, `PG_PORT`, `PG_DATABASE`, and `PG_USER` / `PG_PASSWORD` from the `pg_app_user` and `pg_app_password` variables: the application role that `deploy.sh` then creates with psql. A second `terraform apply` leaves them as they are. The app setting `APPLICATIONINSIGHTS_CONNECTION_STRING` holds the connection string of the Application Insights resource.

## Provisioning Script

[`deploy.sh`](deploy.sh) performs:

- Exports `ARM_SUBSCRIPTION_ID` and `ARM_TENANT_ID` from `az account show` and, when the active `az` cloud is `LocalStack`, `ARM_METADATA_HOSTNAME`: `providers.tf` hardcodes no endpoint and no subscription, so the same files deploy to the emulator and to Azure.
- `terraform init -upgrade`
- `terraform plan -out=tfplan` (passing `pg_admin_password`, `pg_app_user` and `pg_app_password`)
- `terraform apply -auto-approve tfplan`
- Reads outputs (`resource_group_name`, `web_app_name`, `postgres_server_name`, `postgres_fqdn`, `postgres_database_name`).
- Connects to the server as the admin via the public endpoint + firewall rule and creates the `testuser` role, grants schema rights, creates the `activities` table, and seeds three rows.
- Zips the source under `../src` and deploys via `az webapp deploy`.

## Variables

Override any of the variables in [`variables.tf`](variables.tf) by editing [`terraform.tfvars`](terraform.tfvars) or passing `-var` to `terraform plan`. Notable PostgreSQL ones:

| Variable                   | Default          | Description                              |
| -------------------------- | ---------------- | ---------------------------------------- |
| `pg_admin_login`           | `pgadmin`        | Server administrator login               |
| `pg_admin_password`        | `P@ssw0rd1234!`  | Server administrator password (sensitive) |
| `pg_app_user` | `testuser` | Application role the web app connects with |
| `pg_app_password` | `TestP@ssw0rd123` | Application role password (sensitive) |
| `pg_version`               | `16`             | PostgreSQL major version                 |
| `pg_sku_name`              | `B_Standard_B1ms`| Compute SKU                              |
| `pg_storage_mb`            | `32768`          | Storage size in MB                       |
| `pg_backup_retention_days` | `7`              | Backup retention                         |
| `pg_database_name`         | `PlannerDB`      | Application database                     |

For non-dev deployments, set `pg_admin_password` via env var: `PG_ADMIN_PASSWORD=... bash deploy.sh`.

## Telemetry, logs and metrics

Once the web app is deployed, read the telemetry it sent to Application Insights and the logs and metrics the diagnostic settings sent to the workspace. The scripts take the same `PREFIX` and `SUFFIX` as the deployment:

```bash
bash ../scripts/query-telemetry.sh
bash ../scripts/query-logs-and-metrics.sh
```

See [Application Insights](../README.md#application-insights) and [Logs and metrics](../README.md#logs-and-metrics) for what they read.

## Related Documentation

- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
