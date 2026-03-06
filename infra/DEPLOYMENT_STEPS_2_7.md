# EKIP Azure Deployment Runbook - Steps 2 to 7

Run all commands from repo root (`ekip/`) using Windows PowerShell.

## Scope

This runbook covers:
- Step 2: create resource group
- Step 3: deploy infra baseline (`deployApps=false`)
- Step 4: set Key Vault secrets and capture `SecretUriWithVersion` values
- Step 5: build and push images to ACR
- Step 6: deploy apps (`deployApps=true`)
- Step 7: smoke test endpoints

All resources are deployed to:
- Resource Group: `rg-ekip-demo`
- Naming convention: `ekip-<resource>-01`

## Required secret inputs

Set these environment variables before Step 4 (preferred), otherwise the script prompts securely:

```powershell
$env:EKIP_SECRET_OPENAI_API_KEY = "<value>"
$env:EKIP_SECRET_SEARCH_ADMIN_KEY = "<value>"
$env:EKIP_SECRET_SERVICEBUS_CONNECTION_STRING = "<value>"
$env:EKIP_SECRET_STORAGE_CONNECTION_STRING = "<value>"
$env:EKIP_SECRET_COSMOS_KEY = "<value>"
```

The script writes `SecretUriWithVersion` values to `infra/out/kv.secrets.json` for:
- `ekip-openai-api-key`
- `ekip-search-admin-key`
- `ekip-servicebus-connection-string`
- `ekip-storage-connection-string`
- `ekip-cosmos-key`

## Commands (Steps 2 to 7)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\scripts\02_create_rg.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\scripts\03_deploy_infra_baseline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\scripts\04_set_keyvault_secrets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\scripts\05_build_push_images.ps1 -Tag "v0.1.0"
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\scripts\06_deploy_apps.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\infra\scripts\07_smoke_test.ps1
```

## Artifacts generated

- `infra/out/infra.outputs.json`
- `infra/out/kv.secrets.json`
- `infra/out/image.tag.txt`
- `infra/out/apps.outputs.json`
