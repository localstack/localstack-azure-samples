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

# Validate the deployment
bash scripts/validate.sh
```

## Cleanup

```bash
azlocal group delete --name local-aci-rg --yes
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
