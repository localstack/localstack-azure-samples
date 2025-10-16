Function App + Azure Front Door (az CLI)

This sample creates a minimal Python Azure Function App that responds to /{name} with "hello {name}", and configures Azure Front Door (Standard SKU) to route traffic to it. It provides bash scripts that can target either real Azure or LocalStack’s Azure emulation via azlocal interception.

Contents
- scripts/deploy.sh: Creates RG, Storage Account, Linux Consumption Python Function App v4, deploys the function via zip, and sets up Azure Front Door profile, endpoint, origin group, origin, and route.
- scripts/cleanup.sh: Deletes the resource group created by the deployment.
- function/: Minimal Python HTTP-trigger function app (host.json removes /api prefix; route is /{name}).

Prerequisites
- Bash (e.g., Git Bash, WSL, or Linux/macOS shell)
- Azure CLI installed and logged in (az login) for real Azure
- Optional: azlocal (LocalStack’s Azure interception helper) in PATH if you want to target the emulator
- zip utility available in PATH (used for zip deploy)

Quick start
1) Deploy against real Azure (eastus by default):
   bash ./scripts/deploy.sh --name-prefix mydemo

2) Deploy against LocalStack emulator:
   bash ./scripts/deploy.sh --name-prefix mydemo --use-localstack

The script will print:
- Resource group name
- Function default hostname and a sample URL to test (e.g., https://<func>.azurewebsites.net/john)
- AFD endpoint hostname and a sample URL to test (e.g., https://<endpoint>.z01.azurefd.net/john)

Cleanup
- Delete all resources by removing the resource group:
  bash ./scripts/cleanup.sh --resource-group <rg-name>

Notes
- Azure Front Door is a global resource; the script uses Standard_AzureFrontDoor SKU and links the route to the default domain of the endpoint.
- The function removes the /api prefix so you can call /john directly.
- The deployment uses zip deploy; because the function has no heavy dependencies, it should work without additional build steps. If you add dependencies that require native builds, consider using the Azure Functions Core Tools for publishing.

Function App + Azure Front Door (az CLI)

This sample creates a minimal Python Azure Function App that responds to /{name} with "hello {name}", and configures Azure Front Door (Standard SKU) to route traffic to it. It provides bash scripts that can target either real Azure or LocalStack’s Azure emulation via azlocal interception.

Contents
- scripts/deploy.sh: Creates RG, Storage Account, Linux Consumption Python Function App v4, deploys the function via zip, and sets up Azure Front Door profile, endpoint, origin group, origin, and route.
- scripts/cleanup.sh: Deletes the resource group created by the deployment.
- function/: Minimal Python HTTP-trigger function app (host.json removes /api prefix; route is /{name}).

Prerequisites
- Bash (e.g., Git Bash, WSL, or Linux/macOS shell)
- Azure CLI installed and logged in (az login) for real Azure
- Optional: azlocal (LocalStack’s Azure interception helper) in PATH if you want to target the emulator
- zip utility available in PATH (used for zip deploy)

Quick start
1) Deploy against real Azure (eastus by default):
   bash ./scripts/deploy.sh --name-prefix mydemo

2) Deploy against LocalStack emulator:
   bash ./scripts/deploy.sh --name-prefix mydemo --use-localstack

The script will print:
- Resource group name
- Function default hostname and a sample URL to test (e.g., https://<func>.azurewebsites.net/john)
- AFD endpoint hostname and a sample URL to test (e.g., https://<endpoint>.z01.azurefd.net/john)

Deploy to Azure (cloud) and test both endpoints
1) Sign in and select subscription (if needed):
   - az login
   - az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"

2) Run the deployment (avoid --use-localstack to target real Azure):
   - cd samples/function-app-front-door
   - bash ./scripts/deploy.sh --name-prefix mydemo --location eastus

3) Note the outputs printed by the script:
   - Resource Group: rg-mydemo-<suffix>
   - Function Host:  <func>.azurewebsites.net
   - Test Function:  https://<func>.azurewebsites.net/john
   - AFD Endpoint:   <endpoint>.z01.azurefd.net (may take a few minutes to become active)
   - Test via AFD:   https://<endpoint>.z01.azurefd.net/john

4) Test the Function endpoint directly (immediate):
   - Browser: open the "Test Function" URL
   - curl:   curl -i https://<func>.azurewebsites.net/john
   Expected response body:  hello john

5) Test via Azure Front Door (allow a few minutes for readiness):
   - AFD endpoints and routes can take 2–10 minutes to fully propagate.
   - Retry the AFD test URL after a short wait:
     curl -i https://<endpoint>.z01.azurefd.net/john
   Expected response body:  hello john

If you closed the terminal and need to rediscover hostnames
- Get the Function default hostname:
  az functionapp show -g <RESOURCE_GROUP> -n <FUNCTION_APP_NAME> --query defaultHostName -o tsv

- Get the AFD endpoint hostname:
  az afd endpoint show -g <RESOURCE_GROUP> --profile-name <AFD_PROFILE_NAME> --endpoint-name <AFD_ENDPOINT_NAME> --query hostName -o tsv

- If you don’t recall names, list them under the resource group:
  - Function Apps: az functionapp list -g <RESOURCE_GROUP> --query "[].{name:name,host:defaultHostName}"
  - AFD profiles:  az afd profile list -g <RESOURCE_GROUP> --query "[].name"
  - AFD endpoints: az afd endpoint list -g <RESOURCE_GROUP> --profile-name <AFD_PROFILE_NAME> --query "[].{name:name,host:hostName}"

Common notes and troubleshooting
- Windows users: use Git Bash or WSL to run the bash scripts.
- Authentication: the function trigger is Anonymous; no keys required.
- Hostnames: the function is reachable at https://<func>.azurewebsites.net; the AFD default is https://<endpoint>.z01.azurefd.net.
- Application Insights: Azure CLI may auto-provision Application Insights for a new Function App. This sample explicitly disables it by passing --disable-app-insights to az functionapp create. If you want Application Insights, remove that flag and optionally provide --app-insights <NAME> or --app-insights-key <INSTRUMENTATION_KEY>.
- Zip deploy reliability: the script explicitly sets WEBSITE_RUN_FROM_PACKAGE=1, FUNCTIONS_WORKER_RUNTIME=python, and SCM_DO_BUILD_DURING_DEPLOYMENT=false prior to deployment. If a transient zip deployment error occurs, simply run the deploy script again.
- AFD readiness: 2–10 minutes is typical; 15+ minutes in rare cases. You can check status:
  az afd endpoint show -g <RESOURCE_GROUP> --profile-name <AFD_PROFILE_NAME> --endpoint-name <AFD_ENDPOINT_NAME> --query provisioningState -o tsv
- Region and runtime: change with --location and --python-version flags in deploy.sh if needed.

Cleanup
- Delete all resources by removing the resource group (non-blocking delete):
  bash ./scripts/cleanup.sh --resource-group <rg-name>

Notes
- Azure Front Door is a global resource; the script uses Standard_AzureFrontDoor SKU and links the route to the default domain of the endpoint.
- The function removes the /api prefix so you can call /john directly.
- The deployment uses zip deploy; because the function has no heavy dependencies, it should work without additional build steps. If you add dependencies that require native builds, consider using the Azure Functions Core Tools for publishing.

Function App + Azure Front Door (az CLI)

This sample creates a minimal Python Azure Function App that responds to /{name} with "hello {name}", and configures Azure Front Door (Standard SKU) to route traffic to it. It provides bash scripts that can target either real Azure or LocalStack’s Azure emulation via azlocal interception.

Contents
- scripts/deploy.sh: Creates RG, Storage Account, Linux Consumption Python Function App v4, deploys the function via zip, and sets up Azure Front Door profile, endpoint, origin group, origin, and route.
- scripts/cleanup.sh: Deletes the resource group created by the deployment.
- function/: Minimal Python HTTP-trigger function app (host.json removes /api prefix; route is /{name}).

Prerequisites
- Bash (e.g., Git Bash, WSL, or Linux/macOS shell)
- Azure CLI installed and logged in (az login) for real Azure
- Optional: azlocal (LocalStack’s Azure interception helper) in PATH if you want to target the emulator
- zip utility available in PATH (used for zip deploy)

Quick start
1) Deploy against real Azure (eastus by default):
   bash ./scripts/deploy.sh --name-prefix mydemo

2) Deploy against LocalStack emulator:
   bash ./scripts/deploy.sh --name-prefix mydemo --use-localstack

The script will print:
- Resource group name
- Function default hostname and a sample URL to test (e.g., https://<func>.azurewebsites.net/john)
- AFD endpoint hostname and a sample URL to test (e.g., https://<endpoint>.z01.azurefd.net/john)

Cleanup
- Delete all resources by removing the resource group:
  bash ./scripts/cleanup.sh --resource-group <rg-name>

Notes
- Azure Front Door is a global resource; the script uses Standard_AzureFrontDoor SKU and links the route to the default domain of the endpoint.
- The function removes the /api prefix so you can call /john directly.
- The deployment uses zip deploy; because the function has no heavy dependencies, it should work without additional build steps. If you add dependencies that require native builds, consider using the Azure Functions Core Tools for publishing.

Function App + Azure Front Door (az CLI)

This sample creates a minimal Python Azure Function App that responds to /{name} with "hello {name}", and configures Azure Front Door (Standard SKU) to route traffic to it. It provides bash scripts that can target either real Azure or LocalStack’s Azure emulation via azlocal interception.

Contents
- scripts/deploy.sh: Creates RG, Storage Account, Linux Consumption Python Function App v4, deploys the function via zip, and sets up Azure Front Door profile, endpoint, origin group, origin, and route.
- scripts/cleanup.sh: Deletes the resource group created by the deployment.
- function/: Minimal Python HTTP-trigger function app (host.json removes /api prefix; route is /{name}).

Prerequisites
- Bash (e.g., Git Bash, WSL, or Linux/macOS shell)
- Azure CLI installed and logged in (az login) for real Azure
- Optional: azlocal (LocalStack’s Azure interception helper) in PATH if you want to target the emulator
- zip utility available in PATH (used for zip deploy)

Quick start
1) Deploy against real Azure (eastus by default):
   bash ./scripts/deploy.sh --name-prefix mydemo

2) Deploy against LocalStack emulator:
   bash ./scripts/deploy.sh --name-prefix mydemo --use-localstack

The script will print:
- Resource group name
- Function default hostname and a sample URL to test (e.g., https://<func>.azurewebsites.net/john)
- AFD endpoint hostname and a sample URL to test (e.g., https://<endpoint>.z01.azurefd.net/john)

Deploy to Azure (cloud) and test both endpoints
1) Sign in and select subscription (if needed):
   - az login
   - az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"

2) Run the deployment (avoid --use-localstack to target real Azure):
   - cd samples/function-app-front-door
   - bash ./scripts/deploy.sh --name-prefix mydemo --location eastus

3) Note the outputs printed by the script:
   - Resource Group: rg-mydemo-<suffix>
   - Function Host:  <func>.azurewebsites.net
   - Test Function:  https://<func>.azurewebsites.net/john
   - AFD Endpoint:   <endpoint>.z01.azurefd.net (may take a few minutes to become active)
   - Test via AFD:   https://<endpoint>.z01.azurefd.net/john

4) Test the Function endpoint directly (immediate):
   - Browser: open the "Test Function" URL
   - curl:   curl -i https://<func>.azurewebsites.net/john
   Expected response body:  hello john

5) Test via Azure Front Door (allow a few minutes for readiness):
   - AFD endpoints and routes can take 2–10 minutes to fully propagate.
   - Retry the AFD test URL after a short wait:
     curl -i https://<endpoint>.z01.azurefd.net/john
   Expected response body:  hello john

If you closed the terminal and need to rediscover hostnames
- Get the Function default hostname:
  az functionapp show -g <RESOURCE_GROUP> -n <FUNCTION_APP_NAME> --query defaultHostName -o tsv

- Get the AFD endpoint hostname:
  az afd endpoint show -g <RESOURCE_GROUP> --profile-name <AFD_PROFILE_NAME> --endpoint-name <AFD_ENDPOINT_NAME> --query hostName -o tsv

- If you don’t recall names, list them under the resource group:
  - Function Apps: az functionapp list -g <RESOURCE_GROUP> --query "[].{name:name,host:defaultHostName}"
  - AFD profiles:  az afd profile list -g <RESOURCE_GROUP> --query "[].name"
  - AFD endpoints: az afd endpoint list -g <RESOURCE_GROUP> --profile-name <AFD_PROFILE_NAME> --query "[].{name:name,host:hostName}"

Common notes and troubleshooting
- Windows users: use Git Bash or WSL to run the bash scripts.
- Authentication: the function trigger is Anonymous; no keys required.
- Hostnames: the function is reachable at https://<func>.azurewebsites.net; the AFD default is https://<endpoint>.z01.azurefd.net.
- Application Insights: Azure CLI may auto-provision Application Insights for a new Function App. This sample explicitly disables it by passing --disable-app-insights to az functionapp create. If you want Application Insights, remove that flag and optionally provide --app-insights <NAME> or --app-insights-key <INSTRUMENTATION_KEY>.
- Zip deploy reliability: the script explicitly sets WEBSITE_RUN_FROM_PACKAGE=1, FUNCTIONS_WORKER_RUNTIME=python, and SCM_DO_BUILD_DURING_DEPLOYMENT=false prior to deployment. If a transient zip deployment error occurs, simply run the deploy script again.
- AFD readiness: 2–10 minutes is typical; 15+ minutes in rare cases. You can check status:
  az afd endpoint show -g <RESOURCE_GROUP> --profile-name <AFD_PROFILE_NAME> --endpoint-name <AFD_ENDPOINT_NAME> --query provisioningState -o tsv
- Region and runtime: change with --location and --python-version flags in deploy.sh if needed.

Cleanup
- Delete all resources by removing the resource group (non-blocking delete):
  bash ./scripts/cleanup.sh --resource-group <rg-name>

LocalStack emulator notes
- Ensure azlocal is installed and available in PATH. Example quick check: azlocal --help
- Azure Functions Core Tools v4 ('func') must be installed and available in PATH to publish in emulator mode. Verify with: func --version. Install via npm: npm i -g azure-functions-core-tools@4 --unsafe-perm true. See: https://learn.microsoft.com/azure/azure-functions/functions-run-local#install-the-azure-functions-core-tools
- When running with --use-localstack, the scripts isolate the Azure CLI config by setting AZURE_CONFIG_DIR to a temporary directory before starting interception. This prevents issues from a corrupt ~/.azure/clouds.config (e.g., errors like "The suffix 'storage_endpoint' for this cloud is not set ... clouds.config may be corrupt or invalid"). The temporary directory is automatically removed on exit.
- In emulator mode, the deploy script uses funclocal azure functionapp publish (instead of zip deploy to Kudu) to publish the function code, because azurewebsites.net SCM endpoints are not resolvable in LocalStack.
- The scripts use: azlocal start_interception to begin routing az CLI calls to the emulator, and will automatically call azlocal stop_interception on exit.
- If you pass --use-localstack but azlocal or funclocal is not installed or cannot start, the scripts will exit with an error instead of falling back to real Azure. This prevents accidental cloud deployments and avoids subscription errors.
- Make sure LocalStack Pro with Azure support is running and configured before running the scripts in emulator mode.



---
Additional LocalStack notes (update)
- The deploy script now forces a local build for Python when --use-localstack is specified by invoking: funclocal azure functionapp publish <APP_NAME> --python --build local. This avoids relying on SCM/Kudu endpoints that aren’t available in the emulator and prevents the repeating "SCM update poll timed out" messages.
- Ensure your local Python version matches the Function App runtime version. If your local is Python 3.11 but the Function App was created with 3.10 (default), either switch your local environment to 3.10 or create the app with --python-version 3.11:
  bash ./scripts/deploy.sh --name-prefix mydemo --python-version 3.11 --use-localstack
- If you previously saw SCM_* settings being updated repeatedly during publish in emulator mode, re-run the deployment with this updated script; the publish should complete without SCM polling timeouts.
- In emulator mode, the script now sets AzureWebJobsStorage and WEBSITE_CONTENTAZUREFILECONNECTIONSTRING to a LocalStack-specific Storage connection string with explicit Blob/Queue/Table/File endpoints (e.g., https://<acct>.blob.localhost.localstack.cloud:4566). This ensures the package upload/SCM_RUN_FROM_PACKAGE URL points to LocalStack and avoids hangs on "Uploading ...".

---
Offline-friendly Python function for LocalStack
- To ensure emulator publishes don’t attempt to download packages from PyPI, this sample keeps function/requirements.txt empty.
- The function implementation avoids importing azure.functions and simply returns a plain text string. The Functions runtime will serialize this to an HTTP 200 response.
- If you want to use azure.functions types (HttpRequest/HttpResponse) explicitly, add azure-functions to requirements.txt and ensure your environment has internet access (or a local wheel cache) during funclocal --build local.
- This approach works in both emulator and real Azure. For real Azure, zip deploy does not need to build native deps for this sample.
