#!/bin/bash

# Variables
# Every default below can be overridden through the environment, for example
#   SUFFIX=<unique> PG_APP_PASSWORD=<password> bash deploy.sh
# The App Configuration store and the Key Vault have globally unique names on Azure, so a run against a
# real subscription normally needs its own SUFFIX (or PREFIX).
PREFIX="${PREFIX:-local}"
SUFFIX="${SUFFIX:-test}"
LOCATION="${LOCATION:-westeurope}"
TEMPLATE="main.bicep"
PARAMETERS="main.bicepparam"
RESOURCE_GROUP_NAME="${PREFIX}-rg"
APP_CONFIG_NAME="${PREFIX}-appconfig-${SUFFIX}"
KEY_VAULT_NAME="${PREFIX}-keyvault-${SUFFIX}"
VALIDATE_TEMPLATE="${VALIDATE_TEMPLATE:-1}"
USE_WHAT_IF="${USE_WHAT_IF:-0}"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
PG_ADMIN_USER="${PG_ADMIN_USER:-pgadmin}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-P@ssw0rd1234!}"
PG_APP_USER="${PG_APP_USER:-testuser}"
PG_APP_PASSWORD="${PG_APP_PASSWORD:-TestP@ssw0rd123}"
DEPLOY_APP="${DEPLOY_APP:-1}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Validates if the resource group exists in the subscription, if not creates it
echo "Checking if resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]..."
az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null

if [[ $? != 0 ]]; then
	echo "No resource group [$RESOURCE_GROUP_NAME] exists in the subscription [$SUBSCRIPTION_NAME]"
	echo "Creating resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]..."

	# Create the resource group
	az group create \
		--name "$RESOURCE_GROUP_NAME" \
		--location "$LOCATION" \
		--only-show-errors 1> /dev/null

	if [[ $? == 0 ]]; then
		echo "Resource group [$RESOURCE_GROUP_NAME] successfully created in the subscription [$SUBSCRIPTION_NAME]"
	else
		echo "Failed to create resource group [$RESOURCE_GROUP_NAME] in the subscription [$SUBSCRIPTION_NAME]"
		exit 1
	fi
else
	echo "Resource group [$RESOURCE_GROUP_NAME] already exists in the subscription [$SUBSCRIPTION_NAME]"
fi

# Recover the App Configuration store and the key vault if a previous run left them soft-deleted.
# Deleting them only soft-deletes them and their names stay reserved for the retention period, so the
# template deployment below would fail to create them again. Recovering restores them with their contents.
DELETED_APP_CONFIG_LOCATION=$(az appconfig list-deleted \
	--query "[?name=='$APP_CONFIG_NAME'].location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $DELETED_APP_CONFIG_LOCATION ]]; then
	echo "[$APP_CONFIG_NAME] App Configuration store exists in a soft-deleted state in [$DELETED_APP_CONFIG_LOCATION]"
	echo "Recovering the [$APP_CONFIG_NAME] App Configuration store..."

	az appconfig recover \
		--name "$APP_CONFIG_NAME" \
		--location "$DELETED_APP_CONFIG_LOCATION" \
		--yes \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$APP_CONFIG_NAME] App Configuration store successfully recovered"
	else
		echo "Failed to recover the soft-deleted [$APP_CONFIG_NAME] App Configuration store"
		echo "Purge it and re-run this script:"
		echo "  az appconfig purge --name $APP_CONFIG_NAME --location $DELETED_APP_CONFIG_LOCATION --yes"
		exit 1
	fi
fi

# The vault's own location, not $LOCATION: a soft-deleted vault stays in the region it was deleted in.
DELETED_KEY_VAULT_LOCATION=$(az keyvault list-deleted \
	--query "[?name=='$KEY_VAULT_NAME'].properties.location | [0]" \
	--output tsv \
	--only-show-errors 2>/dev/null)

if [[ -n $DELETED_KEY_VAULT_LOCATION ]]; then
	echo "[$KEY_VAULT_NAME] key vault exists in a soft-deleted state in [$DELETED_KEY_VAULT_LOCATION]"
	echo "Recovering the [$KEY_VAULT_NAME] key vault..."

	az keyvault recover \
		--name "$KEY_VAULT_NAME" \
		--location "$DELETED_KEY_VAULT_LOCATION" \
		--only-show-errors 1>/dev/null

	if [[ $? == 0 ]]; then
		echo "[$KEY_VAULT_NAME] key vault successfully recovered"
	else
		echo "Failed to recover the soft-deleted [$KEY_VAULT_NAME] key vault"
		echo "Purge it and re-run this script:"
		echo "  az keyvault purge --name $KEY_VAULT_NAME --location $DELETED_KEY_VAULT_LOCATION"
		exit 1
	fi
fi

# Resolve the object id of the deploying principal. The template grants it Key Vault Secrets Officer on the
# vault, the role a user or pipeline needs to manage the two secrets by hand after the deployment (the
# template itself writes them through Azure Resource Manager). The lookup goes through Microsoft Graph;
# when it fails the assignment is skipped and the deployment still succeeds.
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
	echo "WARNING: could not resolve the object id of the deploying principal [$ACCOUNT_USER_NAME]; the Key Vault Secrets Officer assignment is skipped"
	DEPLOYER_OBJECT_ID=""
fi

# Validates the Bicep template
if [[ $VALIDATE_TEMPLATE == 1 ]]; then
	if [[ $USE_WHAT_IF == 1 ]]; then
		# Execute a deployment What-If operation at resource group scope.
		echo "Previewing changes deployed by Bicep template [$TEMPLATE]..."
		az deployment group what-if \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--template-file "$TEMPLATE" \
			--parameters "$PARAMETERS" \
			--parameters location="$LOCATION" \
			prefix="$PREFIX" \
			suffix="$SUFFIX" \
			pgAdminLogin="$PG_ADMIN_USER" \
			pgAdminPassword="$PG_ADMIN_PASSWORD" \
			pgAppUser="$PG_APP_USER" \
			pgAppPassword="$PG_APP_PASSWORD" \
			deployerPrincipalId="$DEPLOYER_OBJECT_ID" \
			deployerPrincipalType="$DEPLOYER_PRINCIPAL_TYPE" \
			--only-show-errors

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			exit 1
		fi
	else
		# Validate the Bicep template
		echo "Validating Bicep template [$TEMPLATE]..."
		output=$(az deployment group validate \
			--resource-group "$RESOURCE_GROUP_NAME" \
			--template-file "$TEMPLATE" \
			--parameters "$PARAMETERS" \
			--parameters location="$LOCATION" \
			prefix="$PREFIX" \
			suffix="$SUFFIX" \
			pgAdminLogin="$PG_ADMIN_USER" \
			pgAdminPassword="$PG_ADMIN_PASSWORD" \
			pgAppUser="$PG_APP_USER" \
			pgAppPassword="$PG_APP_PASSWORD" \
			deployerPrincipalId="$DEPLOYER_OBJECT_ID" \
			deployerPrincipalType="$DEPLOYER_PRINCIPAL_TYPE" \
			--only-show-errors)

		if [[ $? == 0 ]]; then
			echo "Bicep template [$TEMPLATE] validation succeeded"
		else
			echo "Failed to validate Bicep template [$TEMPLATE]"
			echo "$output"
			exit 1
		fi
	fi
fi

# Deploy the Bicep template
echo "Deploying Bicep template [$TEMPLATE]..."
if DEPLOYMENT_OUTPUTS=$(az deployment group create \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--only-show-errors \
	--template-file "$TEMPLATE" \
	--parameters "$PARAMETERS" \
	--parameters location="$LOCATION" \
	prefix="$PREFIX" \
	suffix="$SUFFIX" \
	pgAdminLogin="$PG_ADMIN_USER" \
	pgAdminPassword="$PG_ADMIN_PASSWORD" \
	pgAppUser="$PG_APP_USER" \
	pgAppPassword="$PG_APP_PASSWORD" \
	deployerPrincipalId="$DEPLOYER_OBJECT_ID" \
	deployerPrincipalType="$DEPLOYER_PRINCIPAL_TYPE" \
	--query 'properties.outputs' -o json); then
	# Extract only the JSON portion (everything from first { to the end)
	DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_OUTPUTS" | sed -n '/{/,$ p')
	echo "Bicep template [$TEMPLATE] deployed successfully. Outputs:"
	echo "$DEPLOYMENT_JSON" | jq .
	WEB_APP_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.webAppName.value')
	POSTGRES_SERVER_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.postgresServerName.value')
	POSTGRES_FQDN_FULL=$(echo "$DEPLOYMENT_JSON" | jq -r '.postgresFqdn.value')
	DATABASE_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.databaseName.value')
	APP_CONFIG_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.appConfigurationName.value')
	APP_CONFIG_ENDPOINT=$(echo "$DEPLOYMENT_JSON" | jq -r '.appConfigurationEndpoint.value')
	KEY_VAULT_NAME=$(echo "$DEPLOYMENT_JSON" | jq -r '.keyVaultName.value')
	echo "Deployment details:"
	echo "Web App Name: $WEB_APP_NAME"
	echo "PostgreSQL Server Name: $POSTGRES_SERVER_NAME"
	echo "PostgreSQL FQDN: $POSTGRES_FQDN_FULL"
	echo "Database Name: $DATABASE_NAME"
	echo "App Configuration Store: $APP_CONFIG_NAME ($APP_CONFIG_ENDPOINT)"
	echo "Key Vault: $KEY_VAULT_NAME"
else
	echo "Failed to deploy Bicep template [$TEMPLATE]"
	exit 1
fi

if [[ -z "$WEB_APP_NAME" || -z "$POSTGRES_SERVER_NAME" || -z "$APP_CONFIG_NAME" || -z "$KEY_VAULT_NAME" ]]; then
	echo "Web App Name, PostgreSQL Server Name, App Configuration Store or Key Vault name is empty. Exiting."
	exit 1
fi

# Verify that the template seeded the five key-values. A failure inside a nested deployment would otherwise
# surface only later, as a web app that cannot load its configuration.
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
	echo "Inspect the deployment operations: az deployment operation group list --resource-group $RESOURCE_GROUP_NAME --name appConfiguration"
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

# Wait until the application database accepts connections. The database is created by the template, and the
# server can take a moment to expose it after the deployment returns.
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
	zip -r "$ZIPFILE" app.py database.py settings.py gunicorn.conf.py static templates requirements.txt

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
