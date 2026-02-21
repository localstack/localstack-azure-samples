#!/bin/bash

# Variables
RESOURCE_GROUP='rg-pgflex'
SERVER_NAME='pgflex-sample'
PRIMARY_DB='sampledb'
SECONDARY_DB='analyticsdb'
WEB_APP_NAME='local-pgflex-webapp-test'
ENVIRONMENT=$(az account show --query environmentName --output tsv)

# Choose the appropriate CLI based on the environment
if [[ $ENVIRONMENT == "LocalStack" ]]; then
	echo "Using azlocal for LocalStack emulator environment."
	AZ="azlocal"
else
	echo "Using standard az for AzureCloud environment."
	AZ="az"
fi

# Check resource group
echo "=== Resource Group ==="
$AZ group show \
	--name "$RESOURCE_GROUP" \
	--output table

# List resources in the resource group
echo ""
echo "=== Resources ==="
$AZ resource list \
	--resource-group "$RESOURCE_GROUP" \
	--output table

# Check PostgreSQL Flexible Server
echo ""
echo "=== PostgreSQL Flexible Server ==="
$AZ postgres flexible-server show \
	--name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--output table

# List databases
echo ""
echo "=== Databases ==="
$AZ postgres flexible-server db list \
	--server-name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--output table

# List firewall rules
echo ""
echo "=== Firewall Rules ==="
$AZ postgres flexible-server firewall-rule list \
	--name "$SERVER_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--output table

# Check Web App
echo ""
echo "=== Web App ==="
$AZ webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--output table

# Get web app URL and test the deployed application
WEB_APP_URL=$($AZ webapp show \
	--name "$WEB_APP_NAME" \
	--resource-group "$RESOURCE_GROUP" \
	--query "defaultHostName" \
	--output tsv)

if [ -z "$WEB_APP_URL" ]; then
	echo "Failed to retrieve Web App URL."
	exit 1
fi

echo ""
echo "=== Testing Web App ==="
echo "Web App URL: https://$WEB_APP_URL"

# Wait for the web app to be ready
echo "Waiting for web app to be ready..."
for i in $(seq 1 30); do
	HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$WEB_APP_URL/" --max-time 10 2>/dev/null)
	if [[ "$HTTP_CODE" == "200" ]]; then
		echo "Web app is responding (HTTP $HTTP_CODE)."
		break
	fi
	echo "  Attempt $i/30: HTTP $HTTP_CODE"
	sleep 5
done

# Test: Create a note via the API
echo ""
echo "Creating a test note..."
CREATE_RESPONSE=$(curl -s -X POST "https://$WEB_APP_URL/api/notes" \
	-H "Content-Type: application/json" \
	-d '{"title":"Test Note","content":"Deployed on LocalStack"}' \
	--max-time 10)
echo "Create response: $CREATE_RESPONSE"

# Test: List notes via the API
echo ""
echo "Listing notes..."
LIST_RESPONSE=$(curl -s "https://$WEB_APP_URL/api/notes" --max-time 10)
echo "List response: $LIST_RESPONSE"

echo ""
echo "=== Validation Complete ==="
