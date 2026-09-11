# Terraform Deployment

This directory contains Terraform modules and a deployment script for provisioning the sample's Azure resources. For details about the sample application, see [Azure Web App with Azure App Configuration and Azure Key Vault](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) (1.5+)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) + [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [Python 3.12+](https://www.python.org/downloads/)
- [PostgreSQL client (`psql`)](https://www.postgresql.org/download/)
- [`jq`](https://jqlang.org/)

```bash
brew install localstack/tap/lstk   # or: npm install -g @localstack/lstk
```

## Architecture Overview

The Terraform configuration uses three providers: [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest) 5.1.0 for every Azure resource, [AzAPI](https://registry.terraform.io/providers/Azure/azapi/latest) 2.12.0 for the App Configuration key-values only, and [time](https://registry.terraform.io/providers/hashicorp/time/latest) for one propagation wait. It provisions:

1. [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-cli).
2. [Azure Virtual Network](https://learn.microsoft.com/azure/virtual-network/virtual-networks-overview) with two subnets:
   - *app-subnet* (delegated to `Microsoft.Web/serverFarms` for the Web App's VNet integration)
   - *pe-subnet* (hosts the three Private Endpoints)
3. [User-assigned managed identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview) `<prefix>-identity-<suffix>` (module `managed_identity`, `azurerm_user_assigned_identity`; outputs the client id the Web App receives and the principal id the role assignments are keyed on).
4. [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview) `<prefix>-keyvault-<suffix>` (module `key_vault`): the vault (`azurerm_key_vault`, Azure RBAC permission model, soft delete, public network access for the deployment, no purge protection), one `azurerm_key_vault_secret` per entry of its sensitive `secrets` map (the root passes `pg-user` and `pg-password` from the variables `pg_app_user` and `pg_app_password`), and, when `deployer_object_id` is set, the [Key Vault Secrets Officer](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-officer) assignment for the deploying principal followed by a `time_sleep` of `rbac_propagation_delay` before the secrets are written: `azurerm_key_vault_secret` uses the Key Vault data plane, which an RBAC vault authorizes only through such an assignment. The module outputs the versionless identifier of every secret and creates the vault's diagnostic settings.
5. [Azure App Configuration store](https://learn.microsoft.com/en-us/azure/azure-app-configuration/overview) `<prefix>-appconfig-<suffix>` (module `app_configuration`): the store (`azurerm_app_configuration`, standard SKU, access keys enabled, public network access for the deployment, soft delete, no purge protection), one `azapi_resource` of type `Microsoft.AppConfiguration/configurationStores/keyValues` per entry of its `key_values` map, and its diagnostic settings. The root passes the five key-values: `PG_HOST`, `PG_PORT` and `PG_DATABASE` as plain values, `PG_USER` and `PG_PASSWORD` as Key Vault references (content type `application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8`, value `jsonencode({ uri = <versionless secret identifier> })` from the Key Vault module outputs). No label.
6. The identity's role assignments (module `role_assignment`, once per grant): [App Configuration Data Reader](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/integration#app-configuration-data-reader) on the store and [Key Vault Secrets User](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-secrets-user) on the vault, on the identity's principal id with `principal_type = "ServicePrincipal"`.
7. Every configurable value of the modules is a variable in the module's `variables.tf` with a description and a default, and every value the root passes is a variable of the root `variables.tf` (SKUs, network access, soft-delete retention, secret and key names, role names, Private DNS zone names, private endpoint sub-resources, diagnostic categories); no resource definition carries a literal.
8. Three [Azure Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-privatednszone), `privatelink.postgres.database.azure.com`, `privatelink.azconfig.io` and `privatelink.vaultcore.azure.net`, each linked to the VNet as `link-to-vnet`.
9. Three [Azure Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview), groups `postgresqlServer`, `configurationStores` and `vault`, each with a `default` DNS zone group.
10. [Azure NAT Gateway](https://learn.microsoft.com/azure/nat-gateway/nat-overview) and one [Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview) per subnet.
11. [Azure Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-overview) and the diagnostic settings of every resource, the store and the vault included.
12. [Azure Database for PostgreSQL flexible server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview): public-access mode, Burstable `Standard_B1ms`, version 16, 32 GiB, HA disabled, the permissive `AllowAllIPs` firewall rule and the `PlannerDB` [database](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-servers).
13. [Azure App Service Plan](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans).
14. [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview) with regional VNet integration, the user-assigned identity (`identity { type = "UserAssigned" }`), and the app settings `Endpoints__AppConfiguration` (the store endpoint) and `AZURE_CLIENT_ID` (the identity client id) next to `LOGIN_NAME`, `WEBSITES_PORT` and the Oryx build flags. **No `PG_*` app setting** is written by Terraform or by `deploy.sh`: the app loads the five settings from the store.

Why AzAPI for the key-values: the azurerm resources `azurerm_app_configuration_key` and `azurerm_app_configuration_feature` write the key-value through the store's data plane and then need the App Configuration DNS suffix of the cloud environment to read it back, a value that an environment discovered from a metadata endpoint, the way Terraform reaches the LocalStack emulator, never carries, so the apply fails after the write and leaves the resource in state. The ARM child resource `Microsoft.AppConfiguration/configurationStores/keyValues` is what Bicep uses too, and AzAPI drives it through Azure Resource Manager alone on both targets. See [Terraform (AzAPI) form of configurationStores/keyValues](https://learn.microsoft.com/en-us/azure/templates/microsoft.appconfiguration/2024-06-01/configurationstores/keyvalues) and the comments in `providers.tf`. The ARM path is subject to the store's [Azure Resource Manager authentication mode](https://learn.microsoft.com/en-us/azure/azure-app-configuration/quickstart-deployment-overview): with the default `Local` mode and access keys enabled the deploying principal only needs Contributor.

### Provider configuration: emulator and Azure

`providers.tf` hardcodes no endpoint and no subscription. `deploy.sh` exports the variables the providers read natively, so the same files run unmodified against both targets:

| Variable                              | Exported when                        | Value                                                     |
| ------------------------------------- | ------------------------------------ | --------------------------------------------------------- |
| `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` | always                              | `az account show`                                          |
| `ARM_METADATA_HOSTNAME`               | active `az cloud` is `LocalStack`    | host of `az cloud show --query endpoints.resourceManager`  |
| `ARM_RESOURCE_MANAGER_ENDPOINT`       | active `az cloud` is `LocalStack`    | `az cloud show --query endpoints.resourceManager`          |
| `ARM_ACTIVE_DIRECTORY_AUTHORITY_HOST` | active `az cloud` is `LocalStack`    | `az cloud show --query endpoints.activeDirectory`          |
| `ARM_RESOURCE_MANAGER_AUDIENCE`       | active `az cloud` is `LocalStack`    | `az cloud show --query endpoints.activeDirectoryResourceId` |
| `ARM_DISABLE_INSTANCE_DISCOVERY`, `ARM_SKIP_PROVIDER_REGISTRATION` | active `az cloud` is `LocalStack` | `true`                        |

azurerm discovers every endpoint from `ARM_METADATA_HOSTNAME`; AzAPI has no metadata discovery and takes the three `ARM_RESOURCE_MANAGER_*` and authority variables. Both authenticate with the Azure CLI session (`use_cli` defaults to true), which `lstk az start-interception` points at the emulator. Against Azure none of the emulator variables is exported and both providers use their public cloud defaults.

## Provisioning Script

[`deploy.sh`](deploy.sh) performs:

- Exports the provider variables above for the active `az cloud`.
- Resolves the object id of the deploying principal (`az ad signed-in-user show` for users, `az ad sp show --id <appId>` for service principals) and passes it as `deployer_object_id`; when Microsoft Graph cannot resolve it, the Key Vault Secrets Officer assignment is skipped with a warning and the role becomes a prerequisite.
- `terraform init -upgrade`
- `terraform plan -out=tfplan` (passing `prefix`, `suffix`, `location`, `pg_admin_login`, `pg_admin_password`, `pg_app_user`, `pg_app_password`, `deployer_object_id`, `deployer_principal_type` and `rbac_propagation_delay`, `0s` on the emulator and `60s` on Azure)
- `terraform apply -auto-approve tfplan`
- Reads the outputs (`resource_group_name`, `web_app_name`, `postgres_server_name`, `postgres_fqdn`, `postgres_database_name`, `app_configuration_name`, `app_configuration_endpoint`, `key_vault_name`) and checks that the store holds the five expected key-values.
- Waits for the `PlannerDB` database to accept connections, then connects to the server as the admin via the public endpoint and the firewall rule, creates the `testuser` role, grants schema rights, creates the `activities` table and seeds the rows. The role credentials are the values already stored in Key Vault; nothing is written to the Web App's app settings.
- Prints the key-values with their content types and the Web App's app settings.
- Zips the source under `../src` and deploys it via `az webapp deploy`.

`deploy.sh` accepts the environment overrides `PREFIX`, `SUFFIX`, `LOCATION`, `PG_ADMIN_USER`, `PG_ADMIN_PASSWORD`, `PG_APP_USER`, `PG_APP_PASSWORD`, `RBAC_PROPAGATION_DELAY` and `DEPLOY_APP`. To prove idempotency, run `terraform plan -detailed-exitcode` with the same variables and environment after the apply: the key-values, secrets and role assignments show no diff. To re-run the configuration from an empty state after `az group delete`, purge the soft-deleted Key Vault and App Configuration store first (`az keyvault purge` and `az appconfig purge`, see the cleanup notes in the main README): otherwise the azurerm provider recovers the soft-deleted vault together with its secrets (`recover_soft_deleted_key_vaults`, enabled by default) and `azurerm_key_vault_secret` refuses to adopt the existing `pg-user` and `pg-password` secrets (`A resource with the ID ... already exists - to be managed via Terraform this resource needs to be imported into the State`). This is the provider's behaviour on Azure and on the emulator alike; the Azure CLI and Bicep variants recover the vault and upsert the secrets, so they can be re-run without a purge. On the emulator a few inherited resources still show read-back drift (NAT gateway zones, App Service plan SKU, some web app and diagnostic-setting attributes), a limitation of the emulator, not of this configuration.

### Alternative: seeding the key-values from deploy.sh

The configuration creates the key-values inside `terraform apply`, so `terraform plan` shows their drift and `terraform destroy` removes them. If the AzAPI path ever proves unreliable on one of the targets, the same key-values can be seeded from `deploy.sh` after the apply, the way the Azure CLI variant does:

1. Pass an empty `key_values` map to the `app_configuration` module in `main.tf` (or remove the `azapi_resource` from the module); the `azapi` provider can then leave `providers.tf` and the module's `versions.tf` too. Never keep both: two owners of the same key-value drift on every apply.
2. After the apply, read `terraform output -raw app_configuration_name`, `key_vault_uri`, `postgres_fqdn` and `postgres_database_name` and run, once per key, `az appconfig kv set --name <store> --key PG_HOST --value <host> --yes` (and `PG_PORT`, `PG_DATABASE`) and `az appconfig kv set-keyvault --name <store> --key PG_USER --secret-identifier <vault URI>/secrets/pg-user --yes` (and `PG_PASSWORD`), probing each key with `az appconfig kv show` first so the step stays idempotent.
3. The seeded key-values must match the AzAPI ones exactly (keys, no label, content types, values), so `validate.sh` and the app behave the same. The commands use the data plane: they need access keys enabled (the default) or `--auth-mode login` with App Configuration Data Owner.

This alternative was not needed during the development of the sample: the AzAPI path works on the emulator and on Azure.

## Variables

Override any of the variables in [`variables.tf`](variables.tf) by editing [`terraform.tfvars`](terraform.tfvars) or passing `-var` to `terraform plan`. Notable ones:

| Variable                     | Default           | Description                                                                                  |
| ---------------------------- | ----------------- | -------------------------------------------------------------------------------------------- |
| `prefix`, `suffix`           | `local`, `test`   | Resource name parts; the store and vault names are globally unique on Azure, use your own suffix |
| `pg_admin_login`             | `pgadmin`         | Server administrator login                                                                   |
| `pg_admin_password`          | `P@ssw0rd1234!`   | Server administrator password (sensitive)                                                    |
| `pg_version`                 | `16`              | PostgreSQL major version                                                                     |
| `pg_sku_name`                | `B_Standard_B1ms` | Compute SKU                                                                                  |
| `pg_storage_mb`              | `32768`           | Storage size in MB                                                                           |
| `pg_backup_retention_days`   | `7`               | Backup retention                                                                             |
| `pg_database_name`           | `PlannerDB`       | Application database                                                                         |
| `pg_app_user`                | `testuser`        | Application role, stored as the `pg-user` secret                                             |
| `pg_app_password`            | `TestP@ssw0rd123` | Application role password (sensitive), stored as the `pg-password` secret                    |
| `app_configuration_sku`      | `standard`        | App Configuration tier (private endpoints need developer, standard or premium)               |
| `key_vault_sku_name`         | `standard`        | Key Vault SKU                                                                                |
| `soft_delete_retention_days` | `7`               | Soft-delete retention of the store and the vault                                             |
| `deployer_object_id`         | `""`              | Object id of the deploying principal, granted Key Vault Secrets Officer (empty skips it)     |
| `deployer_principal_type`    | `User`            | `User`, `ServicePrincipal` or `Group`                                                        |
| `rbac_propagation_delay`     | `60s`             | Wait between the deployer's role assignment and the secret writes (`0s` on the emulator)     |
| `pg_user_secret_name`, `pg_password_secret_name` | `pg-user`, `pg-password` | Names of the two Key Vault secrets                                              |
| `pg_host_key_name`, `pg_port_key_name`, `pg_database_key_name`, `pg_user_key_name`, `pg_password_key_name` | `PG_HOST`, ... | Keys of the five key-values; the application reads exactly these keys |
| `key_vault_reference_content_type` | `application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8` | Content type that marks a Key Vault reference   |
| `app_configuration_public_network_access`, `key_vault_public_network_access_enabled` | `Enabled`, `true` | Public network access of the store and the vault, needed by the deployment |
| `*_private_dns_zone_name`, `*_private_endpoint_subresource_name`, `private_dns_zone_group_name` | Azure defaults | Private DNS zone names, private endpoint sub-resources and zone group name |

For non-dev deployments, set the passwords via env vars: `PG_ADMIN_PASSWORD=... PG_APP_PASSWORD=... bash deploy.sh`.

## Related Documentation

- [AzAPI provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs) and [azapi_resource](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/azapi_resource)
- [azurerm_app_configuration](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/app_configuration), [azurerm_key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault), [azurerm_key_vault_secret](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret), [azurerm_role_assignment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment)
- [Microsoft.AppConfiguration configurationStores/keyValues (Terraform form)](https://learn.microsoft.com/en-us/azure/templates/microsoft.appconfiguration/2024-06-01/configurationstores/keyvalues)
- [LocalStack for Azure Documentation](https://docs.localstack.cloud/azure/)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [lstk GitHub repository](https://github.com/localstack/lstk)
