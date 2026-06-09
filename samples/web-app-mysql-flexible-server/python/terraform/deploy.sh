#!/bin/bash

# Variables
PREFIX='local'
SUFFIX='test'
LOCATION='westeurope'
MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-myadmin}"
MYSQL_ADMIN_PASSWORD="${MYSQL_ADMIN_PASSWORD:-P@ssw0rd1234!}"
MYSQL_APP_USER="${MYSQL_APP_USER:-testuser}"
MYSQL_APP_PASSWORD="${MYSQL_APP_PASSWORD:-TestP@ssw0rd123}"
CURRENT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIPFILE="planner_website.zip"

# Change the current directory to the script's directory
cd "$CURRENT_DIR" || exit

# Intialize Terraform
echo "Initializing Terraform..."
terraform init -upgrade

# Run terraform plan and check for errors
echo "Planning Terraform deployment..."
terraform plan -out=tfplan \
        -var "prefix=$PREFIX" \
        -var "suffix=$SUFFIX" \
        -var "location=$LOCATION" \
        -var "mysql_admin_login=$MYSQL_ADMIN_USER" \
        -var "mysql_admin_password=$MYSQL_ADMIN_PASSWORD"

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
MYSQL_SERVER_NAME=$(terraform output -raw mysql_server_name)
MYSQL_FQDN_FULL=$(terraform output -raw mysql_fqdn)
DATABASE_NAME=$(terraform output -raw mysql_database_name)

if [[ -z "$RESOURCE_GROUP_NAME" || -z "$WEB_APP_NAME" || -z "$MYSQL_SERVER_NAME" ]]; then
	echo "Resource Group Name, Web App Name, or MySQL Server Name is empty. Exiting."
	exit 1
fi

# Split host:port — the LocalStack emulator embeds the dynamically allocated TCP-proxy port
# directly in fullyQualifiedDomainName, mirroring the storage / container registry emulators.
# Real Azure returns just the bare host so MYSQL_PORT defaults to 3306.
MYSQL_FQDN="${MYSQL_FQDN_FULL%%:*}"
if [[ "$MYSQL_FQDN_FULL" == *:* ]]; then
	MYSQL_PORT="${MYSQL_FQDN_FULL##*:}"
else
	MYSQL_PORT=3306
fi
echo "MySQL host = $MYSQL_FQDN, port = $MYSQL_PORT"

echo "Waiting for the [$MYSQL_SERVER_NAME] MySQL flexible server to accept connections..."
MYSQL_READY=0
for attempt in $(seq 1 30); do
	if MYSQL_PWD="$MYSQL_ADMIN_PASSWORD" mysql \
		--host="$MYSQL_FQDN" \
		--port="$MYSQL_PORT" \
		--user="$MYSQL_ADMIN_USER" \
		--protocol=TCP \
		--connect-timeout=5 \
		-e "SELECT 1;" &>/dev/null; then
		MYSQL_READY=1
		echo "MySQL flexible server is accepting connections (attempt $attempt/30)"
		break
	fi
	echo "MySQL flexible server not ready yet (attempt $attempt/30)..."
	sleep 2
done

if [ "$MYSQL_READY" -ne 1 ]; then
	echo "MySQL flexible server did not become reachable after 30 attempts. Exiting."
	exit 1
fi

# Create application user [$MYSQL_APP_USER] on the MySQL flexible server
echo "Creating login [$MYSQL_APP_USER] on the [$MYSQL_SERVER_NAME] MySQL flexible server..."
MYSQL_PWD="$MYSQL_ADMIN_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_ADMIN_USER" \
	--protocol=TCP \
	-e "CREATE USER IF NOT EXISTS '$MYSQL_APP_USER'@'%' IDENTIFIED BY '$MYSQL_APP_PASSWORD';
		GRANT ALL PRIVILEGES ON \`$DATABASE_NAME\`.* TO '$MYSQL_APP_USER'@'%';
		FLUSH PRIVILEGES;"

if [ $? -eq 0 ]; then
	echo "Login [$MYSQL_APP_USER] created successfully"
else
	echo "Failed to create login [$MYSQL_APP_USER]"
	exit 1
fi

# Test connection
echo "Testing connection with user [$MYSQL_APP_USER]..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "SELECT CURRENT_USER() AS user_name, DATABASE() AS db_name, NOW() AS server_time;"

if [ $? -eq 0 ]; then
	echo "Connection test successful with user [$MYSQL_APP_USER]"
else
	echo "Connection test failed with user [$MYSQL_APP_USER]"
	exit 1
fi

# Create [activities] table
echo "Creating [activities] table in the [$DATABASE_NAME] database..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "CREATE TABLE IF NOT EXISTS activities (
			id           VARCHAR(32)  NOT NULL,
			username     VARCHAR(255) NOT NULL,
			activity     TEXT         NOT NULL,
			created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			INDEX idx_activities_username (username),
			INDEX idx_activities_created_at (created_at DESC)
		);"

if [ $? -eq 0 ]; then
	echo "[activities] table created successfully"
else
	echo "Failed to create [activities] table"
	exit 1
fi

# Insert sample data
echo "Inserting sample data into [activities] table..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "INSERT IGNORE INTO activities (id, username, activity) VALUES
			(MD5('paolo_pisa_seed'), 'paolo', 'Visit the Leaning Tower in Pisa'),
			(MD5('paolo_volterra_seed'), 'paolo', 'Explore Etruscan walls in Volterra'),
			(MD5('paolo_san_gimignano_seed'), 'paolo', 'Climb Torre Grossa in San Gimignano'),
			(MD5('paolo_siena_seed'), 'paolo', 'Walk across Piazza del Campo in Siena'),
			(MD5('paolo_montalcino_seed'), 'paolo', 'Taste Brunello wine in Montalcino'),
			(MD5('paolo_pienza_seed'), 'paolo', 'Sample Pecorino cheese in Pienza'),
			(MD5('paolo_florence_seed'), 'paolo', 'Admire Michelangelo''s David in Florence'),
			(MD5('paolo_viareggio_beach_seed'), 'paolo', 'Relax by the beach in Viareggio'),
			(MD5('paolo_viareggio_promenade_seed'), 'paolo', 'Stroll along the Viareggio promenade');"

if [ $? -eq 0 ]; then
	echo "Sample data inserted successfully into [activities] table"
else
	echo "Failed to insert sample data into [activities] table"
	exit 1
fi

# Query sample data
echo "Querying sample data from [activities] table..."
MYSQL_PWD="$MYSQL_APP_PASSWORD" mysql \
	--host="$MYSQL_FQDN" \
	--port="$MYSQL_PORT" \
	--user="$MYSQL_APP_USER" \
	--protocol=TCP \
	--database="$DATABASE_NAME" \
	-e "SELECT * FROM activities;"

if [ $? -eq 0 ]; then
	echo "Sample data queried successfully from [activities] table"
else
	echo "Failed to query sample data from [activities] table"
	exit 1
fi

# Set MYSQL_USER + MYSQL_PASSWORD on the web app to point at the application user
echo "Setting MYSQL_USER=[$MYSQL_APP_USER] and MYSQL_PASSWORD on the [$WEB_APP_NAME] web app..."
az webapp config appsettings set \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--settings MYSQL_USER="$MYSQL_APP_USER" MYSQL_PASSWORD="$MYSQL_APP_PASSWORD" \
	--only-show-errors 1>/dev/null

if [ $? -eq 0 ]; then
	echo "MYSQL_USER and MYSQL_PASSWORD set successfully on the [$WEB_APP_NAME] web app"
else
	echo "Failed to set MYSQL_USER and MYSQL_PASSWORD on the [$WEB_APP_NAME] web app"
	exit 1
fi

# Print the application settings of the web app
echo "Retrieving application settings for web app [$WEB_APP_NAME]..."
az webapp config appsettings list \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME"

# Change current directory to source folder
cd "../src" || exit

# Remove any existing zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Create the zip package of the web app
echo "Creating zip package of the web app..."
zip -r "$ZIPFILE" app.py database.py gunicorn.conf.py static templates requirements.txt

# Deploy the web app
# Deploy the web app
echo "Deploying web app [$WEB_APP_NAME] with zip file [$ZIPFILE]..."
az webapp deploy \
	--resource-group "$RESOURCE_GROUP_NAME" \
	--name "$WEB_APP_NAME" \
	--src-path "$ZIPFILE" \
	--type zip \
	--async true 1>/dev/null

# Remove the zip package of the web app
if [ -f "$ZIPFILE" ]; then
	rm "$ZIPFILE"
fi

# Print the list of resources in the resource group
echo "Listing resources in resource group [$RESOURCE_GROUP_NAME]..."
az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table
