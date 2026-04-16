# Azure Web App with Azure SQL Database and Azure Key Vault

This sample demonstrates a Python Flask single-page web application called *Vacation Planner* hosted on an [Azure Web App](https://learn.microsoft.com/en-us/azure/app-service/overview). The app runs on an Azure App Service Plan and stores activity data in an `activities` table within the `sampledb` database on an [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/) instance. The connection string of the SQL database is stored as a secret in [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/general/overview). The application also retrieves its certificate from Key Vault to serve traffic over HTTPS. 


## Architecture

The following diagram illustrates the architecture of the solution:

![Architecture Diagram](./images/architecture.png)

- **Azure Web App**: Hosts the Python Flask application
- **Azure App Service Plan**: Provides compute resources for the web app
- **Azure SQL Database**: Stores activity data in a relational table
- **Azure Key Vault**: Stores the database connection string and the certificate used to secure HTTPS traffic

## Prerequisites

- [Azure Subscription](https://azure.microsoft.com/free/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Python](https://www.python.org/downloads/)
- [Flask](https://flask.palletsprojects.com/)
- [pyodbc](https://github.com/mkleehammer/pyodbc)
- [Bicep extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep), if you plan to install the sample via Bicep.
- [Terraform](https://developer.hashicorp.com/terraform/downloads), if you plan to install the sample via Terraform.

## Security Configuration

The Vacation Planner Web App supports two common approaches for accessing Azure SQL Database securely:

1. **Using a SQL Database connection string**: Provide a standard SQL connection string using the following environment variables:

- SQL_SERVER: The SQL server container IP address (e.g. 172.17.0.4).
- SQL_DATABASE: The name of the SQL database (e.g.PlannerDB).
- SQL_USERNAME: The username to connect to the SQL database (e.g. testuser).
- SQL_PASSWORD: The password to connect to the SQL database (e.g. TestP@ssw0rd123).

2. **Using Microsoft Entra ID service principal credentials**: Specify the service principal credentials in your environment using the following environment variables:

 - [AZURE_CLIENT_ID](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.environmentcredential): The service principal's client ID.
 - [AZURE_CLIENT_SECRET](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.environmentcredential): One of the service principal's client secrets.
 - [AZURE_TENANT_ID](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.environmentcredential): The Microsoft Entra Tenant ID.

This flexibility allows the app to run securely in Azure or in emulated environments like [LocalStack for Azure](https://azure.localstack.cloud/). The client code supports both authentication modes using [`ClientSecretCredential`](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.clientsecretcredential?view=azure-python) or [`DefaultAzureCredential`](https://learn.microsoft.com/en-us/python/api/azure-identity/azure.identity.defaultazurecredential?view=azure-python) from the Azure SDK.

## Azure Key Vault Integration
The application integrates with Azure Key Vault for managing secrets and certificates:

Secrets: The SQL connection string is stored as a secret in Key Vault. At runtime, the app retrieves it using the Azure Key Vault Secrets SDK. This is configured via the KEY_VAULT_NAME and SECRET_NAME environment variables.

Certificates: A self-signed certificate is created in Key Vault during deployment. The app exposes a GET /api/certificate endpoint that retrieves the certificate using the Azure Key Vault Certificates SDK and returns its name, confirming the integration works. This is configured via the KEYVAULT_URI and CERT_NAME environment variables.

## Deployment

Set up the Azure emulator using the LocalStack for Azure Docker image. Before starting, ensure you have a valid `LOCALSTACK_AUTH_TOKEN` to access the Azure emulator. Refer to the [Auth Token guide](https://docs.localstack.cloud/getting-started/auth-token/?__hstc=108988063.8aad2b1a7229945859f4d9b9bb71e05d.1743148429561.1758793541854.1758810151462.32&__hssc=108988063.3.1758810151462&__hsfp=3945774529) to obtain your Auth Token and set it in the `LOCALSTACK_AUTH_TOKEN` environment variable. The Azure Docker image is available on the [LocalStack Docker Hub](https://hub.docker.com/r/localstack/localstack-azure-alpha). To pull the image, execute:

```bash
docker pull localstack/localstack-azure-alpha
```

Start the LocalStack Azure emulator by running:

```bash
# Set the authentication token
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>

# Start the LocalStack Azure emulator
IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
localstack wait -t 60

# Route all Azure CLI calls to the LocalStack Azure emulator
azlocal start-interception
```

Deploy the application to LocalStack for Azure using one of these methods:

- [Azure CLI Deployment](./scripts/README.md)
- [Bicep Deployment](./bicep/README.md)
- [Terraform Deployment](./terraform/README.md)

All deployment methods have been fully tested against Azure and the LocalStack for Azure local emulator.

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
4. **Via the default hostname**: Call the web app via the default hostname `<web-app-name>.azurewebsites.azure.localhost.localstack.cloud:4566`.

## SQL Server Tooling

You can use [SQL Server Management Studio](https://learn.microsoft.com/en-us/ssms/install/install) to explore and manage your SQL databases. When connecting, use SQL Server Authentication and specify `127.0.0.1,port` as the server name in the Connect dialog box, where `port` is the host port mapped to the container's internal SQL Server port `1433`, as shown in the following picture:

![SQL Server Management Studio](./images/connect.png)

SQL Server Management Studio allows you to manage database objects such as tables and stored procedures, as well as query data, as shown in the following picture:

![SQL Server Management Studio](./images/studio.png)


Alternatively, you can use the [sqlcmd](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility?view=sql-server-ver17&tabs=go%2Cwindows-support&pivots=cs1-bash) to interact with and administer your SQL databases, as shown in the following table:

```bash
~$ sqlcmd -S 172.17.0.4 -d PlannerDB -U testuser -P TestP@ssw0rd123
1> SELECT id, username, SUBSTRING(activity, 1, 20) FROM Activities;
2> GO
id                                   username
------------------------------------ -------------------------------- --------------------
e444433e-f36b-1410-88e7-0034efb7413b paolo                            Go to Paris
e644433e-f36b-1410-88e7-0034efb7413b paolo                            Go to London
e844433e-f36b-1410-88e7-0034efb7413b paolo                            Go to Mexico

(3 rows affected)
```

## References

- [Azure Web Apps Documentation](https://learn.microsoft.com/en-us/azure/app-service/)
- [Azure SQL Database Documentation](https://learn.microsoft.com/en-us/azure/azure-sql/database/)
- [Quickstart: Python Flask on Azure](https://learn.microsoft.com/en-us/azure/app-service/quickstart-python?tabs=flask%2Cbrowser)
- [pyodbc](https://github.com/mkleehammer/pyodbc)
- [Azure Identity Client Library for Python](https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme?view=azure-python)
- [LocalStack for Azure](https://azure.localstack.cloud/)