param location string
param tags object

@description('Foundry Hub resource name.')
param hubName string

@description('Friendly name displayed in Foundry.')
param hubFriendlyName string

@description('Description shown in Foundry.')
param hubDescription string

@description('Resource ID of Application Insights.')
param applicationInsightsId string

@description('Resource ID of Container Registry.')
param containerRegistryId string

@description('Resource ID of Key Vault.')
param keyVaultId string

@description('Resource ID of Storage Account.')
param storageAccountId string

@description('Resource ID of Azure OpenAI (or AI Services) resource to connect.')
param aiServicesId string

@description('Endpoint (target) of Azure OpenAI (or AI Services) resource.')
param aiServicesTarget string

resource aiHub 'Microsoft.MachineLearningServices/workspaces@2023-08-01-preview' = {
  name: hubName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'hub'
  properties: {
    friendlyName: hubFriendlyName
    description: hubDescription

    keyVault: keyVaultId
    storageAccount: storageAccountId
    applicationInsights: applicationInsightsId
    containerRegistry: containerRegistryId
  }

  // Connection used by Foundry to access the Azure OpenAI resource.
  resource openaiConnection 'connections@2024-01-01-preview' = {
    name: '${hubName}-connection-AzureOpenAI'
    properties: {
      category: 'AzureOpenAI'
      target: aiServicesTarget
      authType: 'ApiKey'
      isSharedToAll: true
      credentials: {
        key: '${listKeys(aiServicesId, '2021-10-01').key1}'
      }
      metadata: {
        ApiType: 'Azure'
        ResourceId: aiServicesId
      }
    }
  }
}

output hubId string = aiHub.id
