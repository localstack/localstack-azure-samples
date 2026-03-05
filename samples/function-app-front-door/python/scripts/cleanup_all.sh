#!/usr/bin/env bash
set -euo pipefail

# Unified cleanup script for the consolidated Function App + Azure Front Door samples.
#
# This script deletes the resource group created by scripts/deploy_all.sh. It can read
# the resource group from an env file produced by the deploy script or accept it via flag.
#
# Usage examples:
#   # Using the env file written by deploy_all.sh
#   bash ./scripts/cleanup_all.sh --env-file ./scripts/.last_deploy_all.env --use-localstack
#
#   # Passing the RG directly (works for Azure or LocalStack)
#   bash ./scripts/cleanup_all.sh --resource-group rg-funcafdall-12345
#
# Requirements: az CLI
# Optional: azlocal (LocalStack Azure CLI helper) when cleaning emulator resources

RESOURCE_GROUP=""
ENV_FILE=""
USE_LOCALSTACK="false"

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [--env-file PATH] [--resource-group NAME] [--use-localstack]

Options:
  --env-file PATH         Env file produced by deploy_all.sh (e.g., scripts/.last_deploy_all.env)
  -g, --resource-group    Resource group name to delete
      --use-localstack    Use azlocal interception to target LocalStack emulator
  -h, --help              Show this help
EOF
}

if [[ $# -eq 0 ]]; then print_usage; exit 1; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE=${2:-}; shift 2;;
    -g|--resource-group) RESOURCE_GROUP=${2:-}; shift 2;;
    --use-localstack) USE_LOCALSTACK="true"; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown option: $1" >&2; print_usage; exit 1;;
  esac
done

if [[ -n "$ENV_FILE" ]]; then
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Env file not found: $ENV_FILE" >&2; exit 1
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "Resource group not specified. Provide -g/--resource-group or --env-file pointing to deploy env." >&2
  exit 1
fi

INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  if [[ "$INTERCEPTION_STARTED" == "true" ]] && command -v azlocal >/dev/null 2>&1; then
    set +e; azlocal stop-interception >/dev/null 2>&1 || true; set -e
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
    echo "Error: --use-localstack specified but 'azlocal' was not found in PATH." >&2
    exit 1
  fi
  if azlocal start-interception; then
    INTERCEPTION_STARTED="true"; echo "LocalStack interception started."
  else
    echo "Error: azlocal failed to start interception. Ensure LocalStack is running and azlocal is configured correctly." >&2
    exit 1
  fi
fi

az group delete -n "$RESOURCE_GROUP" --yes --no-wait
echo "Delete requested for resource group '$RESOURCE_GROUP'."
