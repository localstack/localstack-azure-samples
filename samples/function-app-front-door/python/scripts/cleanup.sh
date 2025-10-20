#!/usr/bin/env bash
set -euo pipefail

# Cleanup script: deletes the resource group created by deploy.sh.
# What this script does:
#   1) Parse inputs and validate required parameters
#   2) Optionally enable LocalStack interception via azlocal (for emulator/testing)
#   3) Issue a non-blocking delete for the specified resource group
# Requirements: az CLI
# Optional: azlocal (LocalStack’s Azure interception helper) for emulator mode

# -------------------------------
# 1) Defaults (overridden via flags)
# -------------------------------
RESOURCE_GROUP=""          # Resource group to delete (required)
USE_LOCALSTACK="false"     # If true, try to intercept az calls using azlocal

# -------------------------------
# Usage / help text
# -------------------------------
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
# 2) Argument parsing and validation
# -------------------------------
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
# 3) Optional LocalStack interception lifecycle management
# -------------------------------
INTERCEPTION_STARTED="false"
AZURE_CONFIG_DIR_CREATED="false"
finish() {
  # Ensure we end interception on script exit if it was started
  if [[ "$INTERCEPTION_STARTED" == "true" ]]; then
    if command -v azlocal >/dev/null 2>&1; then
      set +e
      azlocal stop_interception >/dev/null 2>&1 || true
      set -e
    fi
  fi
  # Remove temporary Azure CLI config dir if created
  if [[ "$AZURE_CONFIG_DIR_CREATED" == "true" && -n "${AZURE_CONFIG_DIR:-}" && -d "$AZURE_CONFIG_DIR" ]]; then
    rm -rf "$AZURE_CONFIG_DIR"
  fi
}
trap finish EXIT

if [[ "$USE_LOCALSTACK" == "true" ]]; then
  # Use an isolated Azure CLI config to avoid corrupt ~/.azure/clouds.config issues in emulator mode
  if command -v mktemp >/dev/null 2>&1; then
    AZ_TEMP_CONFIG_DIR="$(mktemp -d)"
  else
    # Fallback if mktemp is unavailable
    AZ_TEMP_CONFIG_DIR="$(pwd)/.azlocal_config_$$"
    mkdir -p "$AZ_TEMP_CONFIG_DIR"
  fi
  export AZURE_CONFIG_DIR="$AZ_TEMP_CONFIG_DIR"
  AZURE_CONFIG_DIR_CREATED="true"
  echo "Using isolated AZURE_CONFIG_DIR at: $AZURE_CONFIG_DIR"

  if ! command -v azlocal >/dev/null 2>&1; then
    echo "Error: --use-localstack specified but 'azlocal' was not found in PATH. Install and configure azlocal (LocalStack Azure CLI helper) and ensure LocalStack is running." >&2
    exit 1
  fi
  if azlocal start_interception; then
    INTERCEPTION_STARTED="true"
    echo "LocalStack interception started."
  else
    echo "Error: azlocal failed to start interception. Ensure LocalStack is running and azlocal is configured correctly." >&2
    exit 1
  fi
fi

# -------------------------------
# 4) Delete the resource group (non-blocking)
# -------------------------------
# --yes confirms deletion without prompt
# --no-wait returns immediately; deletion continues in the background
az group delete -n "$RESOURCE_GROUP" --yes --no-wait

echo "Delete requested for resource group '$RESOURCE_GROUP'."
