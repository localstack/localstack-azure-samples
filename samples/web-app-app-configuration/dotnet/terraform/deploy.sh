#!/bin/bash

# Variables
# Every default below can be overridden through the environment, for example
#   SUFFIX=<unique> PG_APP_PASSWORD=<password> bash deploy.sh
# The App Configuration store and the Key Vault have globally unique names on Azure, so a run against a
# real subscription normally needs its own SUFFIX (or PREFIX).
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION="${LOCATION:-westeurope}"
PG_ADMIN_USER="${PG_ADMIN_USER:-pgadmin}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-P@ssw0rd1234!}"
PG_APP_USER="${PG_APP_USER:-testuser}"
PG_APP_PASSWORD="${PG_APP_PASSWORD:-TestP@ssw0rd123}"
DEPLOY_APP="${DEPLOY_APP:-1}"
RBAC_PROPAGATION_DELAY="${RBAC_PROPAGATION_DELAY:-60s}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Dual-target provider configuration. providers.tf hardcodes nothing: the azurerm and AzAPI providers read
# their endpoints and the target subscription from the ARM_* environment variables exported here.
# - On both targets: the subscription and tenant of the active az account.
# - Only when the active az cloud is LocalStack: the emulator endpoints, taken from the az cloud
#   registration that `lstk az start-interception` created, so nothing is hardcoded here either.
ACTIVE_CLOUD=$(az cloud show --query name --output tsv --only-show-errors)
ARM_SUBSCRIPTION_ID=$(az account show --query id --output tsv --only-show-errors)
ARM_TENANT_ID=$(az account show --query tenantId --output tsv --only-show-errors)
export ARM_SUBSCRIPTION_ID ARM_TENANT_ID

if [[ $ACTIVE_CLOUD == "LocalStack" ]]; then
	RESOURCE_MANAGER_ENDPOINT=$(az cloud show --query endpoints.resourceManager --output tsv --only-show-errors)
	METADATA_HOSTNAME="${RESOURCE_MANAGER_ENDPOINT#https://}"
	export ARM_METADATA_HOSTNAME="${METADATA_HOSTNAME%/}"
	export ARM_RESOURCE_MANAGER_ENDPOINT="$RESOURCE_MANAGER_ENDPOINT"
	ARM_ACTIVE_DIRECTORY_AUTHORITY_HOST=$(az cloud show --query endpoints.activeDirectory --output tsv --only-show-errors)
	ARM_RESOURCE_MANAGER_AUDIENCE=$(az cloud show --query endpoints.activeDirectoryResourceId --output tsv --only-show-errors)
	export ARM_ACTIVE_DIRECTORY_AUTHORITY_HOST ARM_RESOURCE_MANAGER_AUDIENCE
	export ARM_DISABLE_INSTANCE_DISCOVERY=true
	export ARM_SKIP_PROVIDER_REGISTRATION=true
	# The emulator applies role assignments immediately, so the secrets need no propagation wait.
	RBAC_PROPAGATION_DELAY="0s"
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets the emulator at [$ARM_RESOURCE_MANAGER_ENDPOINT]"
else
	echo "Active cloud is [$ACTIVE_CLOUD]: Terraform targets Azure subscription [$ARM_SUBSCRIPTION_ID]"
fi

# Resolve the object id of the deploying principal. azurerm_key_vault_secret writes through the Key Vault
# data plane, so on Azure the principal running terraform apply needs Key Vault Secrets Officer on the
# vault; the configuration assigns it when the id is known. The lookup goes through Microsoft Graph; when
# it fails the assignment is skipped and the role becomes a prerequisite (see the README).
ACCOUNT_USER_TYPE=$(az account show --query user.type --output tsv --only-show-errors)
ACCOUNT_USER_NAME=$(az account show --query user.name --output tsv --only-show-errors)

if [[ $ACCOUNT_USER_TYPE == "user" ]]; then
	DEPLOYER_PRINCIPAL_TYPE="User"
	DEPLOYER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv --only-show-errors 2>/dev/null)
else
	DEPLOYER_PRINCIPAL_TYPE="ServicePrincipal"
	DEPLOYER_OBJECT_ID=$(az ad sp show --id "$ACCOUNT_USER_NAME" --query id --output tsv --only-show-errors 2>/dev/null)
fi

# Microsoft Graph lookups need directory permissions a pipeline principal often lacks. Fall back to the oid
# claim of the CLI's own access token, which identifies the same principal without any Graph call.
if [[ -z $DEPLOYER_OBJECT_ID ]]; then
	DEPLOYER_OBJECT_ID=$(az account get-access-token --query accessToken --output tsv --only-show-errors 2>/dev/null |
		cut -d. -f2 | tr '_-' '/+' | awk '{ pad = length($0) % 4; if (pad == 2) $0 = $0 "=="; else if (pad == 3) $0 = $0 "="; print }' |
		base64 -d 2>/dev/null | jq -r '.oid // empty' 2>/dev/null)
fi

if [[ -n $DEPLOYER_OBJECT_ID ]]; then
	echo "Deploying principal [$ACCOUNT_USER_NAME] ($DEPLOYER_PRINCIPAL_TYPE) has object id [$DEPLOYER_OBJECT_ID]"
else
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the Key Vault Secrets Officer role on the key vault must already be assigned to it"
	DEPLOYER_OBJECT_ID=""
fi

# Intialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

if [[ $? != 0 ]]; then
	echo "Terraform init failed. Exiting."
	exit 1
fi

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
	-var "prefix=$PREFIX" \
	-var "suffix=$SUFFIX" \
	-var "location=$LOCATION" \
	-var "pg_admin_login=$PG_ADMIN_USER" \
	-var "pg_admin_password=$PG_ADMIN_PASSWORD" \
	-var "pg_app_user=$PG_APP_USER" \
	-var "pg_app_password=$PG_APP_PASSWORD" \
	-var "deployer_object_id=$DEPLOYER_OBJECT_ID" \
	-var "deployer_principal_type=$DEPLOYER_PRINCIPAL_TYPE" \
	-var "rbac_propagation_delay=$RBAC_PROPAGATION_DELAY"

if [[ $? != 0 ]]; then
	echo "Terraform plan failed. Exiting."
	exit 1
fi

# Apply the Terraform configuration
echo "Applying Terraform configuration..."
terraform apply -auto-approve tfplan

if [[ $? != 0 ]]; then
	echo "Terraform apply failed. Exiting."
	exit 1
fi

# Get the output values
RESOURCE_GROUP_NAME=$(terraform output -raw resource_group_name)
WEB_APP_NAME=$(terraform output -raw web_app_name)
POSTGRES_SERVER_NAME=$(terraform output -raw postgres_server_name)
POSTGRES_FQDN_FULL=$(terraform output -raw postgres_fqdn)
DATABASE_NAME=$(terraform output -raw postgres_database_name)
APP_CONFIG_NAME=$(terraform output -raw app_configuration_name)
APP_CONFIG_ENDPOINT=$(terraform output -raw app_configuration_endpoint)
KEY_VAULT_NAME=$(terraform output -raw key_vault_name)

if [[ -z "$RESOURCE_GROUP_NAME" || -z "$WEB_APP_NAME" || -z "$POSTGRES_SERVER_NAME" || -z "$APP_CONFIG_NAME" || -z "$KEY_VAULT_NAME" ]]; then
	echo "Resource Group Name, Web App Name, PostgreSQL Server Name, App Configuration Store or Key Vault name is empty. Exiting."
	exit 1
fi

echo "Deployment details:"
echo "Web App Name: $WEB_APP_NAME"
echo "PostgreSQL Server Name: $POSTGRES_SERVER_NAME"
echo "PostgreSQL FQDN: $POSTGRES_FQDN_FULL"
echo "Database Name: $DATABASE_NAME"
echo "App Configuration Store: $APP_CONFIG_NAME ($APP_CONFIG_ENDPOINT)"
echo "Key Vault: $KEY_VAULT_NAME"

# Verify that the configuration seeded the five key-values.
echo "Checking the key-values seeded into the [$APP_CONFIG_NAME] App Configuration store..."
SEEDED_KEYS=$(az appconfig kv list \
	--name "$APP_CONFIG_NAME" \
	--query "[?key=='PG_HOST' || key=='PG_PORT' || key=='PG_DATABASE' || key=='PG_USER' || key=='PG_PASSWORD'].key" \
	--output tsv \
	--only-show-errors | sort | tr '\n' ' ')

if [[ $SEEDED_KEYS == "PG_DATABASE PG_HOST PG_PASSWORD PG_PORT PG_USER " ]]; then
	echo "The [$APP_CONFIG_NAME] App Configuration store holds the five expected key-values"
else
	echo "The [$APP_CONFIG_NAME] App Configuration store does not hold the five expected key-values (found: $SEEDED_KEYS)"
	exit 1
fi

# Split host:port: the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# directly in fullyQualifiedDomainName, mirroring the storage / container registry emulators.
# Real Azure returns just the bare host so the port defaults to 5432.
POSTGRES_FQDN="${POSTGRES_FQDN_FULL%%:*}"
if [[ "$POSTGRES_FQDN_FULL" == *:* ]]; then
	POSTGRES_PORT="${POSTGRES_FQDN_FULL##*:}"
else
	POSTGRES_PORT=5432
fi
echo "PostgreSQL host = $POSTGRES_FQDN, port = $POSTGRES_PORT"

# Wait until the application database accepts connections. The database is created by Terraform, and the
# server can take a moment to expose it after the apply returns.
echo "Waiting for the [$DATABASE_NAME] database on [$POSTGRES_FQDN:$POSTGRES_PORT] to accept connections..."
DATABASE_READY=0
for attempt in $(seq 1 30); do
	if PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
		--host="$POSTGRES_FQDN" \
		--port="$POSTGRES_PORT" \
		--username="$PG_ADMIN_USER" \
		--dbname="$DATABASE_NAME" \
		--no-password \
		--quiet \
		-c "SELECT 1;" 1>/dev/null 2>&1; then
		DATABASE_READY=1
		break
	fi

	if [ "$attempt" -lt 30 ]; then
		echo "Attempt $attempt of 30: the [$DATABASE_NAME] database is not ready yet; retrying in 5 seconds..."
		sleep 5
	fi
done

if [ $DATABASE_READY -eq 1 ]; then
	echo "The [$DATABASE_NAME] database accepts connections"
else
	echo "The [$DATABASE_NAME] database did not become ready in time"
	exit 1
fi

# Create application role [$PG_APP_USER] on the PostgreSQL flexible server. Its name and password are
# already in Key Vault (pg-user, pg-password) and referenced from the App Configuration store; this step
# creates the role the web app logs in with.
echo "Creating login [$PG_APP_USER] on the [$POSTGRES_SERVER_NAME] PostgreSQL flexible server..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "DO \$\$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$PG_APP_USER') THEN
		CREATE ROLE \"$PG_APP_USER\" WITH LOGIN PASSWORD '$PG_APP_PASSWORD';
	END IF;
END
\$\$;"

if [ $? -eq 0 ]; then
	echo "Login [$PG_APP_USER] created successfully"
else
	echo "Failed to create login [$PG_APP_USER]"
	exit 1
fi

# Grant CONNECT on the database to [$PG_APP_USER]
echo "Granting CONNECT on [$DATABASE_NAME] to [$PG_APP_USER]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname=postgres \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT CONNECT ON DATABASE \"$DATABASE_NAME\" TO \"$PG_APP_USER\";"

if [ $? -eq 0 ]; then
	echo "CONNECT granted successfully to [$PG_APP_USER]"
else
	echo "Failed to grant CONNECT to [$PG_APP_USER]"
	exit 1
fi

# Grant schema privileges to [$PG_APP_USER]
echo "Granting schema privileges on [$DATABASE_NAME] to [$PG_APP_USER]..."
PGPASSWORD="$PG_ADMIN_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_ADMIN_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "GRANT USAGE, CREATE ON SCHEMA public TO \"$PG_APP_USER\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"$PG_APP_USER\";
		ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"$PG_APP_USER\";"

if [ $? -eq 0 ]; then
	echo "Schema privileges granted successfully to [$PG_APP_USER]"
else
	echo "Failed to grant schema privileges to [$PG_APP_USER]"
	exit 1
fi

# Test connection
echo "Testing connection with user [$PG_APP_USER]..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	-c "SELECT current_user, current_database(), now();"

if [ $? -eq 0 ]; then
	echo "Connection test successful with user [$PG_APP_USER]"
else
	echo "Connection test failed with user [$PG_APP_USER]"
	exit 1
fi

# Create [activities] table
echo "Creating [activities] table in the [$DATABASE_NAME] database..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "CREATE TABLE IF NOT EXISTS activities (
			id           TEXT PRIMARY KEY,
			username     TEXT NOT NULL,
			activity     TEXT NOT NULL,
			created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_activities_username ON activities(username);
		CREATE INDEX IF NOT EXISTS idx_activities_created_at ON activities(created_at DESC);"

if [ $? -eq 0 ]; then
	echo "[activities] table created successfully"
else
	echo "Failed to create [activities] table"
	exit 1
fi

# Insert sample data
echo "Inserting sample data into [activities] table..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	--set=ON_ERROR_STOP=on \
	-c "INSERT INTO activities (id, username, activity) VALUES
			(md5('paolo_pisa_seed'), 'paolo', 'Visit the Leaning Tower in Pisa'),
      (md5('paolo_volterra_seed'), 'paolo', 'Explore Etruscan walls in Volterra'),
      (md5('paolo_san_gimignano_seed'), 'paolo', 'Climb Torre Grossa in San Gimignano'),
      (md5('paolo_siena_seed'), 'paolo', 'Walk across Piazza del Campo in Siena'),
      (md5('paolo_montalcino_seed'), 'paolo', 'Taste Brunello wine in Montalcino'),
      (md5('paolo_pienza_seed'), 'paolo', 'Sample Pecorino cheese in Pienza'),
      (md5('paolo_florence_seed'), 'paolo', 'Admire Michelangelo''s David in Florence'),
      (md5('paolo_viareggio_beach_seed'), 'paolo', 'Relax by the beach in Viareggio'),
      (md5('paolo_viareggio_promenade_seed'), 'paolo', 'Stroll along the Viareggio promenade')
		ON CONFLICT (id) DO NOTHING;"

if [ $? -eq 0 ]; then
	echo "Sample data inserted successfully into [activities] table"
else
	echo "Failed to insert sample data into [activities] table"
	exit 1
fi

# Query sample data
echo "Querying sample data from [activities] table..."
PGPASSWORD="$PG_APP_PASSWORD" psql \
	--host="$POSTGRES_FQDN" \
	--port="$POSTGRES_PORT" \
	--username="$PG_APP_USER" \
	--dbname="$DATABASE_NAME" \
	--no-password \
	-c "SELECT * FROM activities;"

if [ $? -eq 0 ]; then
	echo "Sample data queried successfully from [activities] table"
else
	echo "Failed to query sample data from [activities] table"
	exit 1
fi

# Print the key-values of the App Configuration store: PG_USER and PG_PASSWORD carry the Key Vault
# reference content type, the other three are plain values. The projection is done client-side with
# --query rather than with --fields: --fields makes the CLI request only those fields from the service,
# and the CLI then fails to build a Key Vault reference whose value was not returned.
echo "Key-values in the [$APP_CONFIG_NAME] App Configuration store:"
az appconfig kv list \
	--name "$APP_CONFIG_NAME" \
	--query "[].{Key:key,ContentType:contentType,Label:label}" \
	--output table \
	--only-show-errors

# Print the application settings of the web app: no PG_* setting, only the store endpoint and the
# identity client id next to the platform settings.
echo "Retrieving application settings for web app [$WEB_APP_NAME]..."
az webapp config appsettings list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--query "[].{Name:name,Value:value}" \
	--output table \
	--only-show-errors

if [[ $DEPLOY_APP == 1 ]]; then
	# Change current directory to source folder
	cd "../src" || exit

	# Remove any existing zip package of the web app
	if [ -f "$ZIPFILE" ]; then
		rm "$ZIPFILE"
	fi

	# Create the zip package of the web app
	echo "Creating zip package of the web app..."
	zip -r "$ZIPFILE" . -x "bin/*" "obj/*" "publish/*" "*.zip"

	# Deploy the web app
	echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
	az webapp deploy \
		--resource-group "$RESOURCE_GROUP_NAME" \
		--name "$WEB_APP_NAME" \
		--src-path "$ZIPFILE" \
		--type zip \
		--async true 1>/dev/null

	if [ $? -eq 0 ]; then
		echo "Web app [$WEB_APP_NAME] deployment started successfully."
	else
		echo "Failed to deploy web app [$WEB_APP_NAME]."
		exit 1
	fi

	# Remove the zip package of the web app
	if [ -f "$ZIPFILE" ]; then
		rm "$ZIPFILE"
	fi

	cd "$CURRENT_DIR" || exit
else
	echo "Skipping the deployment of the web app code (DEPLOY_APP=$DEPLOY_APP)"
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table
