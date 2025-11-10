#!/usr/bin/env bash
set -euo pipefail

# Cleanup resources created by deploy_endpoint_enabled_state.sh
#
# This script deletes the resource group created during deployment.
# It can read parameters from the environment file written by the deploy script
# (scripts/.last_deploy_endpoint_enabled_state.env) or accept flags.
#
# Requirements: az CLI
# Optional for LocalStack mode: azlocal (LocalStack Azure CLI interceptor)
#
# Usage examples:
#  ./cleanup_endpoint_enabled_state.sh -g <resource-group>
#  ./cleanup_endpoint_enabled_state.sh --env-file scripts/.last_deploy_endpoint_enabled_state.env --use-localstack
#

RESOURCE_GROUP=""
ENV_FILE=""
USE_LOCALSTACK="false"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -g, --resource-group STR   Resource group to delete
      --env-file PATH        Optional env file produced by deploy script
      --use-localstack       Use azlocal interception for LocalStack emulator
  -h, --help                 Show this help

If both --env-file and --resource-group are provided, --resource-group takes precedence.
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP=${2:-}; shift 2;;
    --env-file) ENV_FILE=${2:-}; shift 2;;
    --use-localstack) USE_LOCALSTACK="true"; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown option: $1" >&2; print_usage; exit 1;;
  esac
done

# Load from env file if present and RG not provided
if [[ -z "$RESOURCE_GROUP" && -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  echo "Resource group not specified. Provide -g/--resource-group or --env-file pointing to deploy env file." >&2
  exit 1
fi

# Optional LocalStack interception lifecycle
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  if [[ "$INTERCEPTION_STARTED" == "true" ]] && command -v azlocal >/dev/null 2>&1; then
    set +e; azlocal stop_interception >/dev/null 2>&1 || true; set -e
  fi
  if [[ "$AZURE_CONFIG_DIR_CREATED" == "true" && -n "${AZURE_CONFIG_DIR:-}" && -d "$AZURE_CONFIG_DIR" ]]; then
    rm -rf "$AZURE_CONFIG_DIR"
  fi
}
trap finish EXIT

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  if command -v mktemp >/dev/null 2>&1; then AZ_TEMP_CONFIG_DIR="$(mktemp -d)"; else AZ_TEMP_CONFIG_DIR="$(pwd)/.azlocal_config_$$"; mkdir -p "$AZ_TEMP_CONFIG_DIR"; fi
  export AZURE_CONFIG_DIR="$AZ_TEMP_CONFIG_DIR"; AZURE_CONFIG_DIR_CREATED="true"
  echo "Using isolated AZURE_CONFIG_DIR at: $AZURE_CONFIG_DIR"
  if ! command -v azlocal >/dev/null 2>&1; then
    echo "Error: --use-localstack specified but 'azlocal' was not found in PATH. Install and configure azlocal and ensure LocalStack is running." >&2
    exit 1
  fi
  azlocal start_interception && INTERCEPTION_STARTED="true" || { echo "Failed to start azlocal interception" >&2; exit 1; }
fi

# Issue deletion (non-blocking)
az group delete -n "$RESOURCE_GROUP" --yes --no-wait

echo "Delete requested for resource group '$RESOURCE_GROUP'."
