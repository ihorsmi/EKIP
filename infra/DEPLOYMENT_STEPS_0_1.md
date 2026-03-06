# EKIP Azure Deployment Runbook - Steps 0 and 1

This document covers only:
- Step 0: prerequisites automation
- Step 1: stop-ship checks

No resources are deployed by these steps.

## Naming standard

All EKIP resources use `ekip-<resource>-01` naming and deploy into `rg-ekip-demo`.

| Resource | Name |
|---|---|
| Resource Group | `rg-ekip-demo` |
| Azure Container Registry (base) | `ekip-acr-01` |
| Key Vault | `ekip-kv-01` |
| Cosmos DB | `ekip-cosmos-01` |
| Azure AI Search | `ekip-search-01` |
| Service Bus | `ekip-sb-01` |
| Storage Account (base) | `ekip-st-01` |
| Log Analytics Workspace | `ekip-law-01` |
| Container Apps Environment | `ekip-acaenv-01` |
| Backend Container App | `ekip-backend-01` |
| Worker Container App | `ekip-worker-01` |
| Frontend Container App | `ekip-frontend-01` |

Notes for globally unique names:
- Storage Account and ACR are normalized to Azure naming rules (lowercase alphanumeric, no dashes).
- Base names stay anchored to `ekip-st-01` and `ekip-acr-01`.
- If a global-name collision happens, set `uniqueSuffix` to append a short value.
- Example resolved names with `uniqueSuffix=abc`: `ekipst01abc`, `ekipacr01abc`.

## Step 0 - Prerequisites

Run from repo root:

```powershell
pwsh -File .\infra\scripts\00_prereqs.ps1
```

What this script verifies:
- `az`, `az bicep`, `docker`
- Azure login state
- Subscription selection via `AZURE_SUBSCRIPTION_ID` if provided
- Required provider registration

## Step 1 - Stop-ship checks

Run from repo root:

```powershell
pwsh -File .\infra\scripts\01_stopship_check.ps1
```

This script fails fast on:
- Cosmos partition key mismatch
- Missing provider env wiring in Container Apps
- Missing Key Vault secret references for sensitive values
- Missing required managed identity role assignments
- Naming convention drift from `ekip-*-01`

## Environment overrides

PowerShell examples:

```powershell
$env:AZURE_SUBSCRIPTION_ID = "<your-subscription-id>"
$env:AZURE_LOCATION = "westeurope"
```

`AZURE_LOCATION` is consumed by `infra/scripts/_vars.ps1` and defaults to `westeurope`.

## uniqueSuffix collision handling

`infra/bicep/main.bicep` supports:
- `namePrefix` (default `ekip`)
- `nameSuffix` (default `01`)
- `uniqueSuffix` (default empty)

Keep `uniqueSuffix` empty unless Azure reports global name conflicts for Storage/ACR.

Example parameter override:

```json
"uniqueSuffix": {
  "value": "abc"
}
```

## Key Vault secret references expected by Container Apps

`infra/bicep/modules/container-apps.bicep` expects these secret URIs in Key Vault:
- `ekip-openai-api-key`
- `ekip-search-admin-key`
- `ekip-servicebus-connection-string`
- `ekip-storage-connection-string`
- `ekip-cosmos-key`
