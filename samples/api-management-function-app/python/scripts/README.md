# Azure CLI Deployment

This directory contains Bash scripts for deploying and validating the sample using the `lstk` CLI. For details about the sample application, see [API Management and Function App](../README.md).

## Prerequisites

- [LocalStack for Azure](https://docs.localstack.cloud/azure/)
- [Docker](https://docs.docker.com/get-docker/)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [lstk CLI](https://docs.localstack.cloud/aws/developer-tools/running-localstack/lstk/)
- [jq](https://jqlang.org/), `zip` and `openssl`

## Scripts

| Script | Purpose |
|--------|---------|
| `deploy.sh` | Idempotently provisions the Function App and the API Management instance, deploys the function from a zip package, imports the API, applies the policy, and creates the named value, product and subscription. Prints the gateway URL and the command that reads the subscription key. |
| `validate.sh` | Walks the whole chain (direct backend refusal, import, key checks, forwarding, policy effects, CORS preflight, 404, rate limit) and exits non-zero on any failure. |
| `call-api.sh` | Quick user-level smoke test: reads the key, lists the items and reads one of them, honouring a `Retry-After` if the rate limit is still in force. |
