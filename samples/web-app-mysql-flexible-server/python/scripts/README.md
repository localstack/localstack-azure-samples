# Azure CLI Deployment

This directory contains Bash scripts for deploying and validating the sample using the `azlocal` CLI. For details about the sample application, see [Azure Web App with Azure Database for MySQL flexible server](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [Azlocal CLI](https://azure.localstack.cloud/user-guides/sdks/az/)
- [Python 3.12+](https://www.python.org/downloads/)
- [MySQL client (`mysql`)](https://dev.mysql.com/downloads/)
- [`jq`](https://jqlang.org/)

```bash
pip install azlocal
```

## Architecture Overview

[`deploy.sh`](deploy.sh) provisions the same resources as the Bicep and Terraform variants but with raw `az` commands:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli).
2. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview).
3. [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) for both subnets.
4. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview).
5. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) with:
   - *app-subnet*: delegated to `Microsoft.Web/serverFarms` (with NAT gateway).
   - *pe-subnet*: hosts the Private Endpoint (no delegation; `disable-private-endpoint-network-policies=true`).
6. [Azure Database for MySQL flexible server](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/overview): public-access mode, `Burstable / Standard_B1ms`, version 8.0.21, 32 GiB, HA disabled. With a permissive `AllowAllIPs` firewall rule.
7. The `plannerdb` [database](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-create-manage-databases).
8. [Azure Private DNS Zone](https://learn.microsoft.com/azure/dns/private-dns-privatednszone) `privatelink.mysql.database.azure.com`, linked to the VNet.
9. [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview) targeting the MySQL server with group `mysqlServer`, plus the DNS-zone group that auto-registers the A record.
10. A separate application user (`testuser`) created via the `mysql` client, with privileges on `plannerdb`.
11. The `activities` table and the seeded rows.
12. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
13. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with regional VNet integration into *app-subnet*, configured with `MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER=testuser`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`, `LOGIN_NAME`, `WEBSITES_PORT`.

The Web App uses `testuser` — the server-admin login is never written into the Web App's app settings. Use [`validate.sh`](validate.sh) after `deploy.sh` to inspect each Azure resource.

## Usage

```bash
# default secrets
bash deploy.sh

# override secrets via env vars
MYSQL_ADMIN_PASSWORD='<admin-password>' \
MYSQL_APP_PASSWORD='<app-password>' \
bash deploy.sh

# inspect what was deployed
bash validate.sh
```

`deploy.sh` accepts the following environment overrides:

| Env var               | Default            | Description                                   |
| --------------------- | ------------------ | --------------------------------------------- |
| `MYSQL_ADMIN_USER`    | `myadmin`          | Server administrator login                     |
| `MYSQL_ADMIN_PASSWORD`| `P@ssw0rd1234!`    | Server administrator password (sensitive)      |
| `MYSQL_DATABASE_NAME` | `plannerdb`        | Application database                           |
| `MYSQL_APP_USER`      | `testuser`         | Application user used by the Web App            |
| `MYSQL_APP_PASSWORD`  | `TestP@ssw0rd123`  | Password for the application user              |

The script uses [`call-web-app.sh`](call-web-app.sh) (unchanged from the source sample) to demonstrate four ways of hitting the Web App from outside the emulator.
