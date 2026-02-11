# LocalStack for Azure Quick Start

## Overview
You can emulate selected Azure services locally using the LocalStack Azure Docker image. Before you begin, you must export a valid `LOCALSTACK_AUTH_TOKEN`, which unlocks Azure emulation features.  
Refer to the LocalStack Auth Token documentation (e.g. the [Auth Token guide](https://docs.localstack.cloud/references/auth-token/)) to obtain your token and set it as an environment variable.

## Prerequisites
- Docker installed and running
- (Recommended) Docker Compose (v2+)
- LocalStack account with a valid authentication token
- Sufficient disk space for the LocalStack persistent volume

## 1. Pull the Azure Image
```bash
docker pull localstack/localstack-azure-alpha
```

## 2. Choose a Startup Method
You can start the Azure emulator using one of the following methods:

- LocalStack CLI
- Raw `docker run`
- Docker Compose

---

### Option A: LocalStack CLI
Make sure the `localstack` CLI is installed (`pip install localstack` or `brew install localstack/tap/localstack`).

```bash
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
IMAGE_NAME=localstack/localstack-azure-alpha localstack start
```

This:
- Exports your auth token
- Overrides the default image via `IMAGE_NAME`
- Starts LocalStack with Azure emulation enabled in the selected image

To stop:
```bash
localstack stop
```

---

### Option B: Docker CLI
Run the container directly:

```bash
docker run \
  --rm -it \
  -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.localstack/volume:/var/lib/localstack \
  -e LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN:?} \
  localstack/localstack-azure-alpha
```

Notes:
- `-p 4566:4566` exposes the LocalStack edge port
- Mounting the Docker socket enables starting sidecar containers if needed
- The `~/.localstack/volume` mount persists state across restarts
- The `:?` syntax in `${LOCALSTACK_AUTH_TOKEN:?}` fails fast if the variable is unset

---

### Option C: Docker Compose
Create a `docker-compose.yml`:

```yaml
version: "3.8"

services:
  localstack:
    container_name: localstack-main
    image: localstack/localstack-azure-alpha
    ports:
      - "127.0.0.1:4566:4566"
    environment:
      - LOCALSTACK_AUTH_TOKEN=${LOCALSTACK_AUTH_TOKEN:?}
    volumes:
      - "./volume:/var/lib/localstack"
```

Start the service:

```bash
docker compose up
```

(Or with legacy syntax: `docker-compose up`)

To run detached:

```bash
docker compose up -d
```

Stop and remove:

```bash
docker compose down
```

---

## 3. Verify the Emulator
After startup, you can:
- Check logs: `docker logs -f localstack-main`
- Curl the edge endpoint:
  ```bash
  curl -s localhost:4566/_localstack/health | jq
  ```

## 4. Environment Variable Recap
Set the auth token once per shell session:

```bash
export LOCALSTACK_AUTH_TOKEN=<your_auth_token>
```

For shells like Fish:
```fish
set -x LOCALSTACK_AUTH_TOKEN <your_auth_token>
```

For PowerShell:
```powershell
$Env:LOCALSTACK_AUTH_TOKEN = "<your_auth_token>"
```

---

## 5. Cleanup
- Stop containers (`localstack stop`, `docker stop <id>`, or `docker compose down`)
- Remove persisted state if needed:
  ```bash
  rm -rf ~/.localstack/volume
  # or for compose:
  rm -rf ./volume
  ```

---

## Troubleshooting
| Issue | Suggestion |
|-------|------------|
| Auth error | Confirm token validity & export | 
| Port already in use | Change mapping (e.g. `-p 4567:4566`) |
| State not persisting | Verify volume mount path |
| CLI not using Azure image | Ensure `IMAGE_NAME` env var is set before `localstack start` |

---

## Next Steps
- Explore available Azure service endpoints through the LocalStack documentation
- Script integration tests against `http://localhost:4566`
- Combine with Terraform / SDK clients pointing to the LocalStack endpoint

---

Let me know if you’d like an expanded example (e.g. adding a specific Azure service workflow or integrating with a dev container).