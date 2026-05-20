#!/usr/bin/env bash
set -euo pipefail

# Unified cleanup script for the consolidated Function App + Azure Front Door samples.
#
# This script deletes the resource group created by scripts/deploy_all.sh. It can read
# the resource group from an env file produced by the deploy script or accept it via flag.
#
# Usage examples:
#   # Using the env file written by deploy_all.sh
#   bash ./scripts/cleanup_all.sh --env-file ./scripts/.last_deploy_all.env
#
#   # Passing the RG directly
#   bash ./scripts/cleanup_all.sh --resource-group rg-funcafdall-12345
#
# Requirements: az CLI

RESOURCE_GROUP=""
ENV_FILE=""

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [--env-file PATH] [--resource-group NAME]

Options:
  --env-file PATH         Env file produced by deploy_all.sh (e.g., scripts/.last_deploy_all.env)
  -g, --resource-group    Resource group name to delete
  -h, --help              Show this help
EOF
}

if [[ $# -eq 0 ]]; then print_usage; exit 1; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE=${2:-}; shift 2;;
    -g|--resource-group) RESOURCE_GROUP=${2:-}; shift 2;;
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

az group delete -n "$RESOURCE_GROUP" --yes --no-wait
echo "Delete requested for resource group '$RESOURCE_GROUP'."
