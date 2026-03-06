# TROUBLESHOOTING

## `DeploymentNotFound` in `/query`

Cause:

- Azure OpenAI deployment names configured in app are not available in the target Azure OpenAI resource.

Known environment status (March 4, 2026):

- `gpt-4o` and `text-embedding-3-large` provisioning blocked by `InsufficientQuota` in current subscription/region.

Fix:

1. Provision deployments in a region/subscription with quota.
2. Or point EKIP env vars to an external AOAI resource with existing deployments.
3. Confirm both chat and embedding deployment names match environment variables.

## Upload succeeds but ingestion job stalls

Checks:

- Service Bus queue contains/consumes messages.
- Worker Container App is running and healthy.
- Blob URL in job metadata is reachable by worker identity.

## No citations in answer

Checks:

- Verify documents were fully ingested and chunk-indexed.
- Confirm `EKIP_INDEX_PROVIDER=azuresearch` in cloud app settings.
- Verify AI Search index exists and contains chunk documents.

## Auth failures in Azure AD mode

Checks:

- `AUTH_MODE=azure_ad`
- `AZURE_TENANT_ID` and `AZURE_AD_AUDIENCE` are set correctly.
- Token issuer and audience match app registration.

## Secret resolution failures in Container Apps

Checks:

- Key Vault secret URIs (with version) are valid.
- Container Apps identities have `Key Vault Secrets User` role.
- Secret references in Container Apps map to expected env vars.
