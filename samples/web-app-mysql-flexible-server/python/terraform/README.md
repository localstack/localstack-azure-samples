# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning the sample's Azure resources. For details about the sample application, see [Azure Web App with Azure Database for MySQL flexible server](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (1.5+)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/)
- [Python 3.12+](https://www.python.org/downloads/)
- [MySQL client (`mysql`)](https://dev.mysql.com/downloads/)
- [`jq`](https://jqlang.org/)

```bash
pip install azlocal
```

## Architecture Overview

The Terraform configuration provisions:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli).
2. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) with two subnets:
   - *app-subnet* (delegated to `Microsoft.Web/serverFarms` for the Web App's VNet integration)
   - *pe-subnet* (hosts the Private Endpoint to the flex server)
3. [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) `privatelink.mysql.database.azure.com`, linked to the VNet.
4. [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) (group `mysqlServer`).
5. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview).
6. [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview): one per subnet.
7. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview).
8. [Azure Database for MySQL flexible server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/overview): public-access mode, Burstable `Standard_B1ms`, version 8.0.21, 32 GiB, HA disabled. A permissive firewall rule (`AllowAllIPs`, `0.0.0.0–255.255.255.255`) lets the deploy machine reach the server for the post-apply mysql bootstrap.
9. [MySQL database](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-create-manage-databases) `PlannerDB`.
10. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
11. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with regional VNet integration. `MYSQL_HOST` / `MYSQL_PORT` / `MYSQL_DATABASE` are written by Terraform; `MYSQL_USER` and `MYSQL_PASSWORD` are written by `deploy.sh` after the mysql client creates the application user.

## Provisioning Script

[`deploy.sh`](deploy.sh) performs:

- `terraform init -upgrade`
- `terraform plan -out=tfplan` (passing `mysql_admin_password`)
- `terraform apply -auto-approve tfplan`
- Reads outputs (`resource_group_name`, `web_app_name`, `mysql_server_name`, `mysql_fqdn`, `mysql_database_name`).
- Connects to the server as the admin via the public endpoint + firewall rule and creates the `testuser` user, grants privileges, creates the `activities` table, and seeds the rows.
- Sets `MYSQL_USER=testuser` + `MYSQL_PASSWORD=<app-password>` on the Web App via `az webapp config appsettings set`.
- Zips the source under `../src` and deploys via `az webapp deploy`.

## Variables

Override any of the variables in [`variables.tf`](variables.tf) by editing [`terraform.tfvars`](terraform.tfvars) or passing `-var` to `terraform plan`. Notable MySQL ones:

| Variable                      | Default           | Description                              |
| ----------------------------- | ----------------- | ---------------------------------------- |
| `mysql_admin_login`           | `myadmin`         | Server administrator login               |
| `mysql_admin_password`        | `P@ssw0rd1234!`   | Server administrator password (sensitive) |
| `mysql_version`               | `8.0.21`          | MySQL major version                      |
| `mysql_sku_name`              | `B_Standard_B1ms` | Compute SKU                              |
| `mysql_storage_size_gb`       | `32`              | Storage size in GB                       |
| `mysql_backup_retention_days` | `7`               | Backup retention                         |
| `mysql_database_name`         | `PlannerDB`       | Application database                     |

For non-dev deployments, set `mysql_admin_password` via env var: `MYSQL_ADMIN_PASSWORD=... bash deploy.sh`.
