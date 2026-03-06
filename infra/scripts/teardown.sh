#!/usr/bin/env bash
set -euo pipefail

# EKIP infra teardown script
# Usage:
#   ./infra/scripts/teardown.sh <subscriptionId> <resourceGroup>

SUBSCRIPTION_ID="${1:-}"
RG="${2:-}"

if [[ -z "$SUBSCRIPTION_ID" || -z "$RG" ]]; then
  echo "Usage: $0 <subscriptionId> <resourceGroup>"
  exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID"

echo "==> Deleting resource group: $RG"
az group delete --name "$RG" --yes --no-wait

echo "Requested deletion. Monitor in Azure Portal."
