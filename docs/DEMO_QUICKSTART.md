# DEMO_QUICKSTART

This quickstart is optimized for the live Azure demo path.

## Current live endpoints

- Backend: `https://ekip-backend-01.graymushroom-404701f7.northeurope.azurecontainerapps.io`
- Frontend: `https://ekip-frontend-01.graymushroom-404701f7.northeurope.azurecontainerapps.io`
- Active cloud image tag: `v0.1.2`

## Preconditions

- Azure baseline resources already deployed (`rg-ekip-demo`)
- Key Vault secrets set
- Container Apps deployed

## 1) Smoke test API

```powershell
Invoke-WebRequest "https://ekip-backend-01.graymushroom-404701f7.northeurope.azurecontainerapps.io/health"
```

Expected: HTTP 200 with `{"status":"ok"}`.

## 2) Upload synthetic documents

Use files from `data/sample_docs/` only.

- `Azure_LandingZone_Notes.txt`
- `Incident_Response_Runbook.docx`
- `Product_FAQ_EKIP.docx`
- `Employee_Handbook_EKIP.pdf`
- `Security_Access_Policy.txt`

You can use the app UI upload flow or API upload endpoint.

## 3) Ask demo questions

Suggested prompts:

- "What are onboarding requirements for new engineering hires?"
- "List first-response steps for a queue backlog incident."
- "What policy controls are required for privileged access review?"

Expected behavior:

- Response contains grounded citations.
- Response includes suggested actions.
- Conversation appears in history endpoints.

## 4) Validate observability and audit

- Check App Insights / Log Analytics for request telemetry and correlation IDs.
- Verify Cosmos DB has conversation records and agent event logs.

## Known blocker (must disclose in demo)

Azure OpenAI deployments for `gpt-4o` and `text-embedding-3-large` are quota-blocked (`InsufficientQuota`) in the current subscription/region.

Impact:

- Query/chat may fail with `DeploymentNotFound` until deployments are available.

Mitigation during demo:

1. Use a subscription/region with quota.
2. Or configure EKIP against an external Azure OpenAI resource with existing deployments.
