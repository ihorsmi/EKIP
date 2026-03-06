#!/usr/bin/env bash
set -euo pipefail

# EKIP infra deploy script
# Usage:
#   ./infra/scripts/deploy.sh <subscriptionId> <resourceGroup> <location> [uniqueSuffix]
#
# Example:
#   ./infra/scripts/deploy.sh 00000000-0000-0000-0000-000000000000 rg-ekip-demo westeurope

SUBSCRIPTION_ID="${1:-}"
RG="${2:-}"
LOCATION="${3:-}"
UNIQUE_SUFFIX="${4:-}"
NAME_PREFIX="${NAME_PREFIX:-ekip}"
NAME_SUFFIX="${NAME_SUFFIX:-01}"

if [[ -z "$SUBSCRIPTION_ID" || -z "$RG" || -z "$LOCATION" ]]; then
  echo "Usage: $0 <subscriptionId> <resourceGroup> <location> [uniqueSuffix]"
  exit 1
fi

echo "==> Setting subscription"
az account set --subscription "$SUBSCRIPTION_ID"

echo "==> Creating resource group (if missing)"
az group create --name "$RG" --location "$LOCATION" >/dev/null

echo "==> Deploying baseline infra (deployApps=false)"
az deployment group create \
  --resource-group "$RG" \
  --name main \
  --template-file "./infra/bicep/main.bicep" \
  --parameters location="$LOCATION" resourceGroupName="$RG" namePrefix="$NAME_PREFIX" nameSuffix="$NAME_SUFFIX" uniqueSuffix="$UNIQUE_SUFFIX" deployApps=false deployModels=true \
  >/dev/null

echo "==> Outputs"
az deployment group show --resource-group "$RG" --name main --query "properties.outputs" -o jsonc || true

cat <<'NOTE'

Next:
1) Configure secrets in Key Vault and set Container Apps env/secret references.
2) Build and push images:
   - <acr>/ekip-backend:latest
   - <acr>/ekip-worker:latest
   - <acr>/ekip-frontend:latest
3) Re-run deployment with deployApps=true (or trigger GitHub deploy workflow).

NOTE
