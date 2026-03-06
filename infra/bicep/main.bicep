// EKIP baseline Azure infrastructure
// Resource group is created outside this template.

targetScope = 'resourceGroup'

@description('EKIP naming prefix. Keep lowercase.')
param namePrefix string = 'ekip'

@description('EKIP naming suffix.')
param nameSuffix string = '01'

@description('Informational only: expected resource group name for EKIP deployment.')
param resourceGroupName string = 'rg-ekip-demo'

@description('Azure region.')
param location string = resourceGroup().location

@description('Azure region for Cosmos DB account. Override when target region has capacity constraints.')
param cosmosLocation string = location

@description('Azure region for Container Apps environment and apps. Override when ACA capacity is constrained in the default region.')
param appsLocation string = location

@description('Optional short suffix for globally unique resources (ACR and Storage). Keep empty unless needed.')
param uniqueSuffix string = ''

@description('Deploy Container Apps (requires ACR images and Key Vault secrets).')
param deployApps bool = false

@description('Container image tag used for backend/worker/frontend when deployApps=true.')
param imageTag string = 'latest'

@description('SecretUriWithVersion for Key Vault secret ekip-openai-api-key.')
param openAiApiKeySecretId string = ''

@description('SecretUriWithVersion for Key Vault secret ekip-search-admin-key.')
param searchAdminKeySecretId string = ''

@description('SecretUriWithVersion for Key Vault secret ekip-servicebus-connection-string.')
param serviceBusConnectionStringSecretId string = ''

@description('SecretUriWithVersion for Key Vault secret ekip-storage-connection-string.')
param storageConnectionStringSecretId string = ''

@description('SecretUriWithVersion for Key Vault secret ekip-cosmos-key.')
param cosmosKeySecretId string = ''

@description('Deploy Azure OpenAI model deployments.')
param deployModels bool = true

@description('Tags applied to resources.')
param tags object = {
  project: 'EKIP'
  owner: 'hackathon'
}

var uniqueSuffixNormalized = toLower(replace(uniqueSuffix, '-', ''))

var acrBaseName = toLower('${namePrefix}-acr-${nameSuffix}')
var storageBaseName = toLower('${namePrefix}-st-${nameSuffix}')
var keyVaultName = toLower('${namePrefix}-kv-${nameSuffix}')
var cosmosName = toLower('${namePrefix}-cosmos-${nameSuffix}')
var searchName = toLower('${namePrefix}-search-${nameSuffix}')
var serviceBusName = toLower('${namePrefix}-sb-${nameSuffix}')
var logAnalyticsName = toLower('${namePrefix}-law-${nameSuffix}')
var appInsightsName = toLower('${namePrefix}-appi-${nameSuffix}')
var containerAppsEnvName = toLower('${namePrefix}-acaenv-${nameSuffix}')
var backendAppName = toLower('${namePrefix}-backend-${nameSuffix}')
var workerAppName = toLower('${namePrefix}-worker-${nameSuffix}')
var frontendAppName = toLower('${namePrefix}-frontend-${nameSuffix}')
var openAiName = toLower('${namePrefix}-openai-${nameSuffix}')
var foundryHubName = toLower('${namePrefix}-foundry-${nameSuffix}')

// ACR and Storage names are normalized to Azure naming rules (lowercase alphanumeric).
var acrName = toLower(replace('${acrBaseName}${uniqueSuffixNormalized}', '-', ''))
var storageName = toLower(replace('${storageBaseName}${uniqueSuffixNormalized}', '-', ''))

module observability 'modules/observability.bicep' = {
  name: 'observability-${namePrefix}-${nameSuffix}'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    tags: tags
  }
}

module base 'modules/base.bicep' = {
  name: 'base-${namePrefix}-${nameSuffix}'
  params: {
    location: location
    storageAccountName: storageName
    keyVaultName: keyVaultName
    acrName: acrName
    tags: tags
  }
}

module messaging 'modules/messaging.bicep' = {
  name: 'messaging-${namePrefix}-${nameSuffix}'
  params: {
    location: location
    serviceBusName: serviceBusName
    queueName: 'doc-ingest'
    tags: tags
  }
}

module search 'modules/search.bicep' = {
  name: 'search-${namePrefix}-${nameSuffix}'
  params: {
    location: location
    searchServiceName: searchName
    tags: tags
  }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos-${namePrefix}-${nameSuffix}'
  params: {
    location: cosmosLocation
    accountName: cosmosName
    databaseName: 'ekip'
    conversationsContainerName: 'conversations'
    ingestJobsContainerName: 'ingest_jobs'
    agentLogsContainerName: 'agent_logs'
    partitionKeyPath: '/pk'
    tags: tags
  }
}

module openai 'modules/openai.bicep' = {
  name: 'openai-${namePrefix}-${nameSuffix}'
  params: {
    location: location
    openAiAccountName: openAiName
    deployModels: deployModels
    tags: tags
  }
}

module foundryHub 'modules/foundry-hub.bicep' = {
  name: 'foundry-${namePrefix}-${nameSuffix}'
  params: {
    location: location
    hubName: foundryHubName
    hubFriendlyName: 'EKIP Hub'
    hubDescription: 'EKIP hub for Foundry agents, evaluation, and model routing.'
    tags: tags
    storageAccountId: base.outputs.storageAccountId
    keyVaultId: base.outputs.keyVaultId
    containerRegistryId: base.outputs.acrId
    applicationInsightsId: observability.outputs.appInsightsId
    aiServicesId: openai.outputs.openAiId
    aiServicesTarget: openai.outputs.openAiEndpoint
  }
}

module containerApps 'modules/container-apps.bicep' = if (deployApps) {
  name: 'apps-${namePrefix}-${nameSuffix}'
  params: {
    location: appsLocation
    tags: tags
    logAnalyticsId: observability.outputs.logAnalyticsId
    appInsightsConnectionString: observability.outputs.appInsightsConnectionString
    acrLoginServer: base.outputs.acrLoginServer
    acrId: base.outputs.acrId
    backendImage: '${base.outputs.acrLoginServer}/ekip-backend:${imageTag}'
    workerImage: '${base.outputs.acrLoginServer}/ekip-worker:${imageTag}'
    frontendImage: '${base.outputs.acrLoginServer}/ekip-frontend:${imageTag}'
    containerAppsEnvName: containerAppsEnvName
    backendAppName: backendAppName
    workerAppName: workerAppName
    frontendAppName: frontendAppName
    keyVaultId: base.outputs.keyVaultId
    openAiApiKeySecretId: openAiApiKeySecretId
    searchAdminKeySecretId: searchAdminKeySecretId
    serviceBusConnectionStringSecretId: serviceBusConnectionStringSecretId
    storageConnectionStringSecretId: storageConnectionStringSecretId
    cosmosKeySecretId: cosmosKeySecretId
    storageAccountId: base.outputs.storageAccountId
    storageAccountName: base.outputs.storageAccountName
    serviceBusId: messaging.outputs.serviceBusId
    serviceBusName: messaging.outputs.serviceBusName
    serviceBusQueueName: messaging.outputs.queueName
    searchEndpoint: search.outputs.searchEndpoint
    cosmosEndpoint: cosmos.outputs.cosmosEndpoint
    openAiEndpoint: openai.outputs.openAiEndpoint
  }
}

output targetResourceGroupName string = resourceGroupName
output locationName string = location
output namingPrefix string = namePrefix
output namingSuffix string = nameSuffix
output uniqueSuffixApplied string = uniqueSuffixNormalized

output keyVaultName string = keyVaultName
output cosmosAccountName string = cosmosName
output searchServiceName string = searchName
output serviceBusName string = serviceBusName
output logAnalyticsName string = logAnalyticsName
output containerAppsEnvironmentName string = containerAppsEnvName
output backendContainerAppName string = backendAppName
output workerContainerAppName string = workerAppName
output frontendContainerAppName string = frontendAppName

output storageBaseName string = storageBaseName
output acrBaseName string = acrBaseName
output storageAccountName string = base.outputs.storageAccountName
output acrName string = base.outputs.acrName
output acrLoginServer string = base.outputs.acrLoginServer
output backendUrl string = deployApps ? containerApps.outputs.backendUrl : ''
output frontendUrl string = deployApps ? containerApps.outputs.frontendUrl : ''
