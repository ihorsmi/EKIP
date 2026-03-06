#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_vars.sh"

has_failure=0

write_pass() {
  echo "PASS: $1"
}

write_fail() {
  echo "FAIL: $1" >&2
  has_failure=1
}

assert_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    write_fail "Missing required tool: $1"
    return 1
  fi
  write_pass "Found tool: $1"
}

write_section "Step 0 - Tool checks"

assert_cmd az || true
assert_cmd docker || true

if command -v az >/dev/null 2>&1; then
  if az_cli_version="$(az version --query '"azure-cli"' -o tsv 2>/dev/null)"; then
    echo "Azure CLI version: ${az_cli_version}"
  else
    write_fail "Unable to read Azure CLI version."
  fi

  if az_bicep_version="$(az bicep version 2>/dev/null | head -n 1)"; then
    echo "Azure Bicep version: ${az_bicep_version}"
  else
    write_fail "Azure CLI bicep component is missing. Run: az bicep install"
  fi
fi

if command -v docker >/dev/null 2>&1; then
  if docker_version="$(docker version --format '{{.Client.Version}}' 2>/dev/null)"; then
    echo "Docker version: ${docker_version}"
  elif docker_version="$(docker --version 2>/dev/null)"; then
    echo "Docker version: ${docker_version}"
  else
    write_fail "Unable to read Docker version."
  fi
fi

if [[ ${has_failure} -ne 0 ]]; then
  echo "One or more required local tools are missing." >&2
  exit 1
fi

write_section "Step 0 - Azure login and subscription"

if ! account_json="$(az account show -o json 2>/dev/null)"; then
  write_fail "Azure CLI is not logged in. Run: az login"
  exit 1
fi

if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
  echo "Setting subscription from AZURE_SUBSCRIPTION_ID: ${AZURE_SUBSCRIPTION_ID}"
  if ! az account set --subscription "${AZURE_SUBSCRIPTION_ID}" >/dev/null; then
    write_fail "Failed to set subscription ${AZURE_SUBSCRIPTION_ID}."
    exit 1
  fi
  sub_name="$(az account show --query name -o tsv)"
  sub_id="$(az account show --query id -o tsv)"
  write_pass "Active subscription set to ${sub_name} (${sub_id})."
else
  echo "AZURE_SUBSCRIPTION_ID is not set. Using current subscription."
  sub_name="$(az account show --query name -o tsv)"
  sub_id="$(az account show --query id -o tsv)"
  tenant_id="$(az account show --query tenantId -o tsv)"
  echo "Subscription: ${sub_name} (${sub_id})"
  echo "Tenant: ${tenant_id}"
fi

write_section "Step 0 - Provider registration"

providers=(
  Microsoft.App
  Microsoft.OperationalInsights
  Microsoft.KeyVault
  Microsoft.CognitiveServices
  Microsoft.Search
  Microsoft.DocumentDB
  Microsoft.Storage
  Microsoft.ServiceBus
  Microsoft.ContainerRegistry
)

for provider in "${providers[@]}"; do
  state="$(az provider show --namespace "${provider}" --query registrationState -o tsv 2>/dev/null || true)"
  if [[ "${state}" == "Registered" ]]; then
    write_pass "${provider} already registered."
    continue
  fi

  echo "Registering ${provider} (current state: ${state})..."
  if ! az provider register --namespace "${provider}" --wait >/dev/null; then
    write_fail "Provider registration failed for ${provider}."
    continue
  fi

  state_after="$(az provider show --namespace "${provider}" --query registrationState -o tsv 2>/dev/null || true)"
  if [[ "${state_after}" == "Registered" ]]; then
    write_pass "${provider} registered."
  else
    write_fail "${provider} registration state is '${state_after}'."
  fi
done

if [[ ${has_failure} -ne 0 ]]; then
  echo "Step 0 failed. Resolve the failures above and rerun." >&2
  exit 1
fi

write_section "Step 0 complete"
echo "Prerequisites are ready for EKIP Azure deployment checks."
echo "Next command:"
echo "  pwsh -File ./infra/scripts/01_stopship_check.ps1"
