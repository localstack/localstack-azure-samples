# Azure Web App with CosmosDB for MongoDB

This sample demonstrates a Python Flask single-page web application called *Vacation Planner* hosted on an [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview). The app runs on an Azure App Service Plan and stores activity data in the `activities` collection of the `sampledb` MongoDB database on an [Azure CosmosDB for MongoDB](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction) account.

## Overview

The solution implements a vacation planning workflow that:

 - Hosts a Flask web app enabling users to browse and manage vacation activities
 - Persists activity data in a MongoDB database on Azure CosmosDB
 - Demonstrates cloud-native architecture using Azure PaaS services

## Architecture

The following diagram illustrates the architecture of the solution:

![Architecture Diagram](./images/architecture.png)

- **Azure Web App**: Hosts the Python Flask application
- **Azure App Service Plan**: Provides compute resources for the web app
- **Azure CosmosDB for MongoDB**: Stores activity data in a MongoDB collection

## Prerequisites

- [Azure Subscription](https://azure.microsoft.com/free/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Python 3.11+](https://www.python.org/downloads/)
- [Flask](https://flask.palletsprojects.com/)
- [pymongo](https://pymongo.readthedocs.io/en/stable/)
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep), if you plan to install the sample via Bicep.
- [Terraform](https://developer.hashicorp.com/terraform/downloads), if you plan to install the sample via Terraform.

## Security Configuration

The Vacation Planner Web App supports two secure approaches for accessing the MongoDB database:

1. **Using an Azure CosmosDB account connection string**: Specify the MongoDB connection string in the `COSMOSDB_CONNECTION_STRING` environment variable.
2. **Using Microsoft Entra ID service principal credentials**: Specify the service principal credentials in your environment using the following environment variables:

 - [AZURE_CLIENT_ID](https://learn.microsoft.com/en-us/dotnet/api/azure.identity.environmentcredential?view=azure-dotnet): The client (application) ID of an App Registration in the Microsoft Entra ID Tenant.
 - [AZURE_CLIENT_SECRET](https://learn.microsoft.com/en-us/dotnet/api/azure.identity.environmentcredential?view=azure-dotnet):
 - [AZURE_TENANT_ID](https://learn.microsoft.com/en-us/dotnet/api/azure.identity.environmentcredential?view=azure-dotnet): The Microsoft Entra Tenant ID.

This flexibility allows the app to run securely in Azure or in emulated environments like [LocalStack for Azure](https://azure.localstack.cloud/). The client code supports both authentication modes using [`ClientSecretCredential`](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.clientsecretcredential?view=azure-python) or [`DefaultAzureCredential`](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.defaultazurecredential?view=azure-python) from the Azure SDK.

### 1. MongoDB Connection String

Use a [MongoDB connection string](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/connect-account) to connect directly to CosmosDB without requiring Azure credentials:

```python
from src.cosmosdb import CosmosDBClient

# Direct connection with connection string
cosmos_client = CosmosDBClient(
    connection_string="mongodb://<username>:<password>@<host>:10255/?ssl=true"
)
cosmos_client.insert_document("sampledb", "activities", {"activity": "Hiking"})
```

Or use the `from_connection_string()` factory method:

```python
# From cosmosdb.py
cosmos_client = CosmosDBClient.from_connection_string(
    "mongodb://myaccount:key@myaccount.mongo.cosmos.azure.com:10255/?ssl=true"
)
```

### 2. Service principals in Microsoft Entra ID

Use [service principals in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/architecture/service-accounts-principal) to access CosmosDB through the Azure Management API. This approach enables both database operations and management capabilities:

```python
from src.cosmosdb import CosmosDBClient

# Initialize with service principal credentials
cosmos_client = CosmosDBClient(
    azure_client_id="<client_id>",
    azure_client_secret="<client_secret>",
    azure_tenant_id="<tenant_id>",
    azure_subscription_id="<subscription_id>",
    account_name="mycosmosaccount",
    resource_group_name="myresourcegroup",
    database_name="sampledb",
    collection_name="activities"
)

# Perform database operations
cosmos_client.insert_document({"activity": "Kayaking"})
```

Alternatively, use environment variables with the `from_env()` method for simpler configuration:

```python
# From cosmosdb.py - reads from environment variables:
# AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
cosmos_client = CosmosDBClient.from_env()
```

### Authentication Implementation

The `CosmosDBClient` class uses `ClientSecretCredential` internally when initialized with service principal credentials:

```python
# Excerpt from cosmosdb.py
from azure.identity import ClientSecretCredential

def _get_credential(self) -> ClientSecretCredential:
    """Get or create Azure ClientSecretCredential."""
    if self._credential:
        return self._credential

    self._credential = ClientSecretCredential(
        client_id=self.client_id,
        client_secret=self.client_secret,
        tenant_id=self.tenant_id
    )
    logger.info("Azure credential created successfully")
    return self._credential
```

This credential authenticates with the Azure CosmosDB Management API to retrieve connection strings and manage resources. For local development or when running in Azure environments with service principals, you can also use `DefaultAzureCredential`, which automatically selects the appropriate authentication method based on the execution context.

## Configuration

The following environment variables configure the application:

```bash
AZURE_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
COSMOSDB_BASE_URL=https://<cosmos-db-account-name>.documents.azure.com:443/
COSMOSDB_DATABASE_NAME=sampledb
COSMOSDB_COLLECTION_NAME=activities
USERNAME=paolo
```

If you deploy the sample application using any of the following deployment methods, these settings are automatically configured for you.

## Deployment

1. Set up the Azure emulator using the LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/?__hstc=108988063.8aad2b1a7229945859f4d9b9bb71e05d.1743148429561.1758793541854.1758810151462.32&__hssc=108988063.3.1758810151462&__hsfp=3945774529) to obtain your Auth Token and set it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the image, execute:

   ```bash
   docker pull localstack/localstack-azure-alpha
   ```

2. Start the LocalStack Azure emulator by running:

   ```bash
   export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
   IMAGE_NAME=localstack/localstack-azure-alpha localstack start
   ```

3. Deploy the application to LocalStack for Azure using one of these methods:

    - [Azure CLI Deployment](./scripts/README.md)
    - [Bicep Deployment](./bicep/README.md)
    - [Terraform Deployment](./terraform/README.md)

> **Note**  
> When you deploy the application to LocalStack for Azure for the first time, the initialization process involves downloading and building Docker images. This is a one-time operation—subsequent deployments will be significantly faster. Depending on your internet connection and system resources, this initial setup may take several minutes.

## Test

1. Retrieve the port published and mapped to port 80 by the Docker container hosting the emulated Web App.
2. Open a web browser and navigate to `http://localhost:<published-port>`.
3. If the deployment was successful, you will see the following user interface for adding and removing activities:

![Architecture Diagram](./images/vacation-planner.png)

You can use the `call-web-app.sh` Bash script below to call the web app. The script demonstrates three methods for calling web apps:

1. **Through the LocalStack for Azure emulator**: Call the web app via the emulator using its default host name. The emulator acts as a proxy to the web app.
2. **Via localhost and host port mapped to the container's port**: Use `127.0.0.1` with the host port mapped to the container's port `80`.
3. **Via container IP address**: Use the app container's IP address on port `80`. This technique is only available when accessing the web app from the Docker host machine.

```bash
#!/bin/bash

get_docker_container_name_by_prefix() {
	local app_prefix="$1"
	local container_name

	# Check if Docker is running
	if ! docker info >/dev/null 2>&1; then
		echo "Error: Docker is not running" >&2
		return 1
	fi

	echo "Looking for containers with names starting with [$app_prefix]..." >&2

	# Find the container using grep
	container_name=$(docker ps --format "{{.Names}}" | grep "^${app_prefix}" | head -1)

	if [ -z "$container_name" ]; then
		echo "Error: No running container found with name starting with [$app_prefix]" >&2
		return 1
	fi

	echo "Found matching container [$container_name]" >&2
	echo "$container_name"
}

get_docker_container_ip_address_by_name() {
	local container_name="$1"
	local ip_address

	if [ -z "$container_name" ]; then
		echo "Error: Container name is required" >&2
		return 1
	fi

	# Get IP address
	ip_address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name")

	if [ -z "$ip_address" ]; then
		echo "Error: Container [$container_name] has no IP address assigned" >&2
		return 1
	fi

	echo "$ip_address"
}

get_docker_container_port_mapping() {
	local container_name="$1"
	local container_port="$2"
	local host_port

	if [ -z "$container_name" ] || [ -z "$container_port" ]; then
		echo "Error: Container name and container port are required" >&2
		return 1
	fi

	# Get host port mapping
	host_port=$(docker inspect -f "{{(index (index .NetworkSettings.Ports \"${container_port}/tcp\") 0).HostPort}}" "$container_name")

	if [ -z "$host_port" ]; then
		echo "Error: No host port mapping found for container [$container_name] port [$container_port]" >&2
		return 1
	fi

	echo "$host_port"
}

call_web_app() {
	# Get the web app name
	echo "Getting web app name..."
	web_app_name=$(azlocal webapp list --query '[0].name' --output tsv)

	if [ -n "$web_app_name" ]; then
		echo "Web app [$web_app_name] successfully retrieved."
	else
		echo "Error: No web app found"
		exit 1
	fi

	# Get the resource group name
	echo "Getting resource group name for web app [$web_app_name]..."
	resource_group_name=$(azlocal webapp list --query '[0].resourceGroup' --output tsv)

	if [ -n "$resource_group_name" ]; then
		echo "Resource group [$resource_group_name] successfully retrieved."
	else
		echo "Error: No resource group found for web app [$web_app_name]"
		exit 1
	fi

	# Get the the default host name of the web app
	echo "Getting the default host name of the web app [$web_app_name]..."
	app_host_name=$(azlocal webapp show \
		--name "$web_app_name" \
		--resource-group "$resource_group_name" \
		--query 'defaultHostName' \
		--output tsv)

	if [ -n "$app_host_name" ]; then
		echo "Web app default host name [$app_host_name] successfully retrieved."
	else
		echo "Error: No web app default host name found"
		exit 1
	fi

	# Get the Docker container name
	echo "Finding container name with prefix [ls-$web_app_name]..."
	container_name=$(get_docker_container_name_by_prefix "ls-$web_app_name")

	if [ $? -eq 0 ] && [ -n "$container_name" ]; then
		echo "Container [$container_name] found successfully"
	else
		echo "Failed to get container name"
		exit 1
	fi

	# Get the container IP address
	echo "Getting IP address for container [$container_name]..."
	container_ip=$(get_docker_container_ip_address_by_name "$container_name")
	player_name='Leo'
	game_session='1'

	if [ $? -eq 0 ] && [ -n "$container_ip" ]; then
		echo "IP address [$container_ip] retrieved successfully for container [$container_name]"
	else
		echo "Failed to get container IP address"
		exit 1
	fi

	# Get the mapped host port for web app HTTP trigger (internal port 80)
	echo "Getting the host port mapped to internal port 80 in container [$container_name]..."
	host_port=$(get_docker_container_port_mapping "$container_name" "80")
	
	if [ $? -eq 0 ] && [ -n "$host_port" ]; then
		echo "Mapped host port [$host_port] retrieved successfully for container [$container_name]"
	else
		echo "Failed to get mapped host port for container [$container_name]"
		exit 1
	fi

	# Retrieve LocalStack proxy port
	proxy_port=$(curl http://localhost:4566/_localstack/proxy -s | jq '.proxy_port')

	if [ -n "$proxy_port" ]; then
		# Call the web app via emulator proxy
		echo "Calling web app [$web_app_name] via emulator..."
		curl --proxy "http://localhost:$proxy_port/" -s "http://$app_host_name/" 1> /dev/null
		
		if [ $? == 0 ]; then
			echo "Web app call via emulator proxy port [$proxy_port] succeeded."
		else
			echo "Web app call via emulator proxy port [$proxy_port] failed."
		fi
	else
		echo "Failed to retrieve LocalStack proxy port"
	fi
	
	if [ -n "$container_ip" ]; then
		# Call the web app via the container IP address
		echo "Calling web app [$web_app_name] via container IP address [$container_ip]..."
		curl -s "http://$container_ip/" 1> /dev/null

		if [ $? == 0 ]; then
			echo "Web app call via container IP address [$container_ip] succeeded."
		else
			echo "Web app call via container IP address [$container_ip] failed."
		fi
	else
		echo "Failed to retrieve container IP address"
	fi

	if [ -n "$host_port" ]; then
		# Call the web app via the host port
		echo "Calling web app [$web_app_name] via host port [$host_port]..."
		curl -s "http://127.0.0.1:$host_port/" 1> /dev/null

		if [ $? == 0 ]; then
			echo "Web app call via host port [$host_port] succeeded."
		else
			echo "Web app call via host port [$host_port] failed."
		fi
	else
		echo "Failed to retrieve host port"
	fi
}

call_web_app
```

You can also access the web app using the following methods:

1. **Through the LocalStack for Azure emulator** - Call the Functions App endpoint exposed by the emulator, which proxies requests to your Azure Functions app



2. **Via localhost** - Use `127.0.0.1` with the host port mapped to the container's port `80`

## References

- [Azure Web Apps Documentation](https://learn.microsoft.com/en-us/azure/app-service/)
- [Azure CosmosDB for MongoDB API](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/introduction)
- [Quickstart: Python Flask on Azure](https://learn.microsoft.com/en-us/azure/app-service/quickstart-python?tabs=flask%2Cbrowser)
- [Quickstart: CosmosDB for MongoDB](https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/quickstart?tabs=azure-portal)
- [Azure Identity Client Library for Python](https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme?view=azure-python)
- [LocalStack for Azure](https://azure.localstack.cloud/)