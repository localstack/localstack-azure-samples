# Vacation Planner on Azure Container Instances

A sample application demonstrating how to deploy a containerized Flask web app using four Azure services:

- **Azure Blob Storage** — Stores vacation activities as JSON blobs
- **Azure Key Vault** — Stores the storage connection string as a secret
- **Azure Container Registry (ACR)** — Hosts the Docker container image
- **Azure Container Instances (ACI)** — Runs the containerized application

## Architecture

```
┌──────────────┐     store conn     ┌──────────────┐  env vars   ┌──────────────┐
│   Storage    │ ──── string ────►  │   KeyVault   │ ─────────►  │     ACI      │
│   Account    │                    │  (secrets)   │             │  (container  │
└──────────────┘                    └──────────────┘             │   group)     │
       ▲                                                        │              │
       │ read/write activities                                  │              │
       └────────────────────────────────────────────────────────┤              │
                                                                │              │
┌──────────────┐     image pull                                 │              │
│     ACR      │ ────────────────────────────────────────────►  │              │
│  (registry)  │  (registry credentials)                        └──────────────┘
└──────────────┘
```

**Deployment flow:** The deploy script creates Storage and Key Vault first, stores the storage connection string as a secret, creates ACR and pushes the container image, then creates an ACI container group that pulls from ACR with the secrets injected as environment variables.

**At runtime:** The Flask app reads the storage connection string from its environment, connects to Blob Storage, and provides a web UI for managing vacation activities (add, edit, delete).

## Prerequisites

- [LocalStack](https://docs.localstack.cloud/getting-started/installation/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [azlocal](https://pypi.org/project/azlocal/) (`pip install azlocal`)

## Quick Start

```bash
# Start LocalStack Azure
IMAGE_NAME=localstack/localstack-azure-alpha localstack start -d
localstack wait -t 60

# Login
azlocal login
azlocal start_interception

# Deploy all services
cd python
bash scripts/deploy.sh

# Validate the deployment (includes stop/start/restart lifecycle tests)
bash scripts/validate.sh
```

## Advanced Deployment

The advanced script demonstrates additional ACI features on top of the basic deployment:

- **Init containers** — Run a health-check container before the app starts
- **emptyDir volumes** — Shared temporary storage between init and app containers
- **Secret volumes** — Config files decoded from base64 and mounted read-only
- **Secure environment variables** — Connection string hidden from API responses
- **DNS name label / FQDN** — Generates a fully qualified domain name

```bash
# Run the basic deployment first, then:
bash scripts/deploy-advanced.sh
```

## Cleanup

```bash
# Removes all resources created by deploy.sh and deploy-advanced.sh
bash scripts/cleanup.sh
```

## Application

The Vacation Planner is a Flask web application with a Bootstrap UI that lets users manage vacation activities. Activities are stored as JSON blobs in Azure Blob Storage, organized by username.

### Endpoints

| Route | Method | Description |
|-------|--------|-------------|
| `/` | GET | View all activities |
| `/` | POST | Add or update an activity |
| `/delete/<id>` | POST | Delete an activity |
| `/update/<id>` | GET | Edit an activity |
| `/health` | GET | Health check |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `AZURE_STORAGE_CONNECTION_STRING` | Blob Storage connection string (from Key Vault) |
| `BLOB_CONTAINER_NAME` | Name of the blob container for activities |
| `LOGIN_NAME` | Username for the activity list (default: "paolo") |

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/deploy.sh` | Basic deployment: Storage, Key Vault, ACR, ACI with env vars and DNS label |
| `scripts/validate.sh` | Validates all resources and exercises ACI lifecycle (get, list, logs, exec, stop, start, restart) |
| `scripts/deploy-advanced.sh` | Advanced deployment: init containers, emptyDir/secret volumes, secure env vars |
| `scripts/cleanup.sh` | Removes all resources created by deploy.sh and deploy-advanced.sh |

## ACI Features Demonstrated

| Feature | Basic Deploy | Advanced Deploy |
|---------|:---:|:---:|
| Container group create | x | x |
| Public IP + ports | x | x |
| Environment variables | x | x |
| Registry credentials (ACR) | x | x |
| CPU / memory resources | x | x |
| DNS name label / FQDN | x | x |
| Secure environment variables | | x |
| Init containers | | x |
| emptyDir volumes | | x |
| Secret volumes | | x |
| Stop / Start / Restart | validate.sh | |
| List container groups | validate.sh | |
| Logs with --tail | validate.sh | |
| Container exec | validate.sh | |
