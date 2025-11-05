#!/usr/bin/env bash
set -euo pipefail

# Cleanup script for the simplified routes-specificity deployment
# (deploy_routes_specificity_single.sh).
#
# What this script does:
# - Deletes the resource group created by the deploy script. That RG contains:
#     • 1 Storage account
#     • 1 Function App
#     • 1 AFD Profile + Endpoint
#     • 1 AFD Origin Group + 1 Origin
#     • 2 AFD Routes (/* catch-all and /john specific)
# - Uses a non-blocking delete (az group delete --no-wait) so you can keep working
#   while Azure/LocalStack performs the deletion in the background.
#
# When to use --use-localstack:
# - If you deployed with --use-localstack, pass it here as well so az commands are
#   intercepted by azlocal and applied to your LocalStack instance.
#
# Requirements: az CLI
# Optional: azlocal (LocalStack Azure helper) for emulator mode
#

print_usage() {
  cat <<EOF
Usage: $(basename "$0") -g <resource-group> [--use-localstack]

Options:
  -g, --resource-group STR  Resource group to delete (required)
      --use-localstack      Use azlocal interception for LocalStack emulator
  -h, --help                Show this help
EOF
}

# -------------------------------
# Parse arguments
# -------------------------------
RESOURCE_GROUP=""
USE_LOCALSTACK="false"

if [[ $# -eq 0 ]]; then print_usage; exit 1; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP=${2:-}; shift 2;;
    --use-localstack) USE_LOCALSTACK="true"; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown option: $1" >&2; print_usage; exit 1;;
  esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "--resource-group is required" >&2
  exit 1
fi

# -------------------------------
# Optional LocalStack interception lifecycle
# -------------------------------
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  # Stop interception if it was started
  if [[ "$INTERCEPTION_STARTED" == "true" ]] && command -v azlocal >/dev/null 2>&1; then
    set +e
    azlocal stop_interception >/dev/null 2>&1 || true
    set -e
  fi
  # Remove temporary Azure CLI config dir if created
  if [[ "$AZURE_CONFIG_DIR_CREATED" == "true" && -n "${AZURE_CONFIG_DIR:-}" && -d "$AZURE_CONFIG_DIR" ]]; then
    rm -rf "$AZURE_CONFIG_DIR"
  fi
}
trap finish EXIT

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  # Use an isolated Azure CLI config to avoid modifying your global ~/.azure when intercepting
  if command -v mktemp >/dev/null 2>&1; then
    AZ_TEMP_CONFIG_DIR="$(mktemp -d)"
  else
    AZ_TEMP_CONFIG_DIR="$(pwd)/.azlocal_config_$$"; mkdir -p "$AZ_TEMP_CONFIG_DIR"
  fi
  export AZURE_CONFIG_DIR="$AZ_TEMP_CONFIG_DIR"; AZURE_CONFIG_DIR_CREATED="true"
  echo "Using isolated AZURE_CONFIG_DIR at: $AZURE_CONFIG_DIR"

  if ! command -v azlocal >/dev/null 2>&1; then
    echo "Error: --use-localstack specified but 'azlocal' was not found in PATH. Install and configure azlocal and ensure LocalStack is running." >&2
    exit 1
  fi
  if azlocal start_interception; then
    INTERCEPTION_STARTED="true"; echo "LocalStack interception started."
  else
    echo "Error: azlocal failed to start interception. Ensure LocalStack is running and azlocal is configured correctly." >&2
    exit 1
  fi
fi

# -------------------------------
# Delete the resource group (non-blocking)
# -------------------------------
az group delete -n "$RESOURCE_GROUP" --yes --no-wait

echo "Delete requested for resource group '$RESOURCE_GROUP'."
