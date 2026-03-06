param location string
param tags object
param logAnalyticsId string
param appInsightsConnectionString string

param acrId string
param acrLoginServer string
param backendImage string
param workerImage string
param frontendImage string

param containerAppsEnvName string
param backendAppName string
param workerAppName string
param frontendAppName string

param keyVaultId string
param openAiApiKeySecretId string
param searchAdminKeySecretId string
param serviceBusConnectionStringSecretId string
param storageConnectionStringSecretId string
param cosmosKeySecretId string

param storageAccountId string
param storageAccountName string
param serviceBusId string
param serviceBusName string
param serviceBusQueueName string
param searchEndpoint string
param cosmosEndpoint string
param openAiEndpoint string

param cosmosDatabaseName string = 'ekip'
param cosmosConversationsContainerName string = 'conversations'
param cosmosIngestJobsContainerName string = 'ingest_jobs'
param cosmosAgentLogsContainerName string = 'agent_logs'
param searchIndexName string = 'ekip-knowledge'
param openAiChatDeployment string = 'gpt-4o'
param openAiEmbedDeployment string = 'text-embedding-3-large'
param blobContainerName string = 'documents'

var laCustomerId = reference(logAnalyticsId, '2023-09-01').customerId
var laSharedKey = listKeys(logAnalyticsId, '2023-09-01').primarySharedKey
var acrPullIdentityName = '${containerAppsEnvName}-acrpull-mi'
var backendExternalUrl = 'https://${backendAppName}.${env.properties.defaultDomain}'
var frontendExternalUrl = 'https://${frontendAppName}.${env.properties.defaultDomain}'

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var serviceBusDataSenderRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
var serviceBusDataReceiverRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: last(split(acrId, '/'))
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(split(storageAccountId, '/'))
}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: last(split(serviceBusId, '/'))
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: last(split(keyVaultId, '/'))
}

resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: acrPullIdentityName
  location: location
  tags: tags
}

resource acrPullIdentityAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acrPullIdentity.id, 'acrpull')
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: acrPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPullIdentityKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, acrPullIdentity.id, 'keyvaultsecretsuser')
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: acrPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource env 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: laCustomerId
        sharedKey: laSharedKey
      }
    }
    zoneRedundant: false
  }
}

resource backend 'Microsoft.App/containerApps@2023-05-01' = {
  name: backendAppName
  location: location
  tags: tags
  dependsOn: [
    acrPullIdentityAcrPull
    acrPullIdentityKeyVaultSecretsUser
  ]
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      registries: [
        {
          server: acrLoginServer
          identity: acrPullIdentity.id
        }
      ]
      secrets: [
        {
          name: 'openai-api-key'
          keyVaultUrl: openAiApiKeySecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'search-admin-key'
          keyVaultUrl: searchAdminKeySecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'servicebus-connection-string'
          keyVaultUrl: serviceBusConnectionStringSecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'storage-connection-string'
          keyVaultUrl: storageConnectionStringSecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'cosmos-key'
          keyVaultUrl: cosmosKeySecretId
          identity: acrPullIdentity.id
        }
      ]
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
      }
    }
    template: {
      containers: [
        {
          name: 'backend'
          image: backendImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'EKIP_ENV', value: 'prod' }
            { name: 'LOG_LEVEL', value: 'INFO' }
            { name: 'ALLOWED_ORIGINS', value: '${frontendExternalUrl},http://localhost:3000' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
            { name: 'EKIP_STATE_PROVIDER', value: 'cosmos' }
            { name: 'EKIP_QUEUE_PROVIDER', value: 'servicebus' }
            { name: 'EKIP_STORAGE_PROVIDER', value: 'azureblob' }
            { name: 'EKIP_INDEX_PROVIDER', value: 'azuresearch' }
            { name: 'AZURE_OPENAI_ENDPOINT', value: openAiEndpoint }
            { name: 'AZURE_OPENAI_CHAT_DEPLOYMENT', value: openAiChatDeployment }
            { name: 'AZURE_OPENAI_EMBED_DEPLOYMENT', value: openAiEmbedDeployment }
            { name: 'AZURE_OPENAI_API_KEY', secretRef: 'openai-api-key' }
            { name: 'AZURE_SEARCH_ENDPOINT', value: searchEndpoint }
            { name: 'AZURE_SEARCH_INDEX_NAME', value: searchIndexName }
            { name: 'AZURE_SEARCH_ADMIN_KEY', secretRef: 'search-admin-key' }
            { name: 'AZURE_SERVICEBUS_QUEUE', value: serviceBusQueueName }
            { name: 'AZURE_SERVICEBUS_FQDN', value: '${serviceBusName}.servicebus.windows.net' }
            { name: 'AZURE_SERVICEBUS_CONNECTION_STRING', secretRef: 'servicebus-connection-string' }
            { name: 'AZURE_STORAGE_ACCOUNT_URL', value: 'https://${storageAccountName}.blob.core.windows.net' }
            { name: 'AZURE_STORAGE_CONTAINER_RAW', value: blobContainerName }
            { name: 'AZURE_STORAGE_CONNECTION_STRING', secretRef: 'storage-connection-string' }
            { name: 'AZURE_COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'AZURE_COSMOS_DB', value: cosmosDatabaseName }
            { name: 'AZURE_COSMOS_CONTAINER_CONVERSATIONS', value: cosmosConversationsContainerName }
            { name: 'AZURE_COSMOS_CONTAINER_INGEST_JOBS', value: cosmosIngestJobsContainerName }
            { name: 'AZURE_COSMOS_CONTAINER_AGENT_LOGS', value: cosmosAgentLogsContainerName }
            { name: 'AZURE_COSMOS_KEY', secretRef: 'cosmos-key' }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

resource worker 'Microsoft.App/containerApps@2023-05-01' = {
  name: workerAppName
  location: location
  tags: tags
  dependsOn: [
    acrPullIdentityAcrPull
    acrPullIdentityKeyVaultSecretsUser
  ]
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      registries: [
        {
          server: acrLoginServer
          identity: acrPullIdentity.id
        }
      ]
      secrets: [
        {
          name: 'openai-api-key'
          keyVaultUrl: openAiApiKeySecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'search-admin-key'
          keyVaultUrl: searchAdminKeySecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'servicebus-connection-string'
          keyVaultUrl: serviceBusConnectionStringSecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'storage-connection-string'
          keyVaultUrl: storageConnectionStringSecretId
          identity: acrPullIdentity.id
        }
        {
          name: 'cosmos-key'
          keyVaultUrl: cosmosKeySecretId
          identity: acrPullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: workerImage
          command: [
            'python'
            '-m'
            'worker'
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'EKIP_ENV', value: 'prod' }
            { name: 'LOG_LEVEL', value: 'INFO' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
            { name: 'EKIP_STATE_PROVIDER', value: 'cosmos' }
            { name: 'EKIP_QUEUE_PROVIDER', value: 'servicebus' }
            { name: 'EKIP_STORAGE_PROVIDER', value: 'azureblob' }
            { name: 'EKIP_INDEX_PROVIDER', value: 'azuresearch' }
            { name: 'AZURE_OPENAI_ENDPOINT', value: openAiEndpoint }
            { name: 'AZURE_OPENAI_CHAT_DEPLOYMENT', value: openAiChatDeployment }
            { name: 'AZURE_OPENAI_EMBED_DEPLOYMENT', value: openAiEmbedDeployment }
            { name: 'AZURE_OPENAI_API_KEY', secretRef: 'openai-api-key' }
            { name: 'AZURE_SEARCH_ENDPOINT', value: searchEndpoint }
            { name: 'AZURE_SEARCH_INDEX_NAME', value: searchIndexName }
            { name: 'AZURE_SEARCH_ADMIN_KEY', secretRef: 'search-admin-key' }
            { name: 'AZURE_SERVICEBUS_QUEUE', value: serviceBusQueueName }
            { name: 'AZURE_SERVICEBUS_FQDN', value: '${serviceBusName}.servicebus.windows.net' }
            { name: 'AZURE_SERVICEBUS_CONNECTION_STRING', secretRef: 'servicebus-connection-string' }
            { name: 'AZURE_STORAGE_ACCOUNT_URL', value: 'https://${storageAccountName}.blob.core.windows.net' }
            { name: 'AZURE_STORAGE_CONTAINER_RAW', value: blobContainerName }
            { name: 'AZURE_STORAGE_CONNECTION_STRING', secretRef: 'storage-connection-string' }
            { name: 'AZURE_COSMOS_ENDPOINT', value: cosmosEndpoint }
            { name: 'AZURE_COSMOS_DB', value: cosmosDatabaseName }
            { name: 'AZURE_COSMOS_CONTAINER_CONVERSATIONS', value: cosmosConversationsContainerName }
            { name: 'AZURE_COSMOS_CONTAINER_INGEST_JOBS', value: cosmosIngestJobsContainerName }
            { name: 'AZURE_COSMOS_CONTAINER_AGENT_LOGS', value: cosmosAgentLogsContainerName }
            { name: 'AZURE_COSMOS_KEY', secretRef: 'cosmos-key' }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

resource frontend 'Microsoft.App/containerApps@2023-05-01' = {
  name: frontendAppName
  location: location
  tags: tags
  dependsOn: [
    acrPullIdentityAcrPull
    acrPullIdentityKeyVaultSecretsUser
  ]
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      registries: [
        {
          server: acrLoginServer
          identity: acrPullIdentity.id
        }
      ]
      ingress: {
        external: true
        targetPort: 3000
        transport: 'auto'
      }
    }
    template: {
      containers: [
        {
          name: 'frontend'
          image: frontendImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'NEXT_PUBLIC_API_BASE_URL', value: backendExternalUrl }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

resource backendAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, backend.name, 'acrpull')
  scope: acr
  dependsOn: [
    backend
  ]
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: backend.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, worker.name, 'acrpull')
  scope: acr
  dependsOn: [
    worker
  ]
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: worker.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource frontendAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, frontend.name, 'acrpull')
  scope: acr
  dependsOn: [
    frontend
  ]
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: frontend.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource backendStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, backend.name, 'storageblobdatacontributor')
  scope: storage
  dependsOn: [
    backend
  ]
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: backend.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, worker.name, 'storageblobdatacontributor')
  scope: storage
  dependsOn: [
    worker
  ]
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: worker.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource backendServiceBusSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, backend.name, 'servicebusdatasender')
  scope: serviceBus
  dependsOn: [
    backend
  ]
  properties: {
    roleDefinitionId: serviceBusDataSenderRoleDefinitionId
    principalId: backend.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource backendServiceBusReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, backend.name, 'servicebusdatareceiver')
  scope: serviceBus
  dependsOn: [
    backend
  ]
  properties: {
    roleDefinitionId: serviceBusDataReceiverRoleDefinitionId
    principalId: backend.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerServiceBusSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, worker.name, 'servicebusdatasender')
  scope: serviceBus
  dependsOn: [
    worker
  ]
  properties: {
    roleDefinitionId: serviceBusDataSenderRoleDefinitionId
    principalId: worker.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerServiceBusReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, worker.name, 'servicebusdatareceiver')
  scope: serviceBus
  dependsOn: [
    worker
  ]
  properties: {
    roleDefinitionId: serviceBusDataReceiverRoleDefinitionId
    principalId: worker.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource backendKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, backend.name, 'keyvaultsecretsuser')
  scope: keyVault
  dependsOn: [
    backend
  ]
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: backend.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource workerKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, worker.name, 'keyvaultsecretsuser')
  scope: keyVault
  dependsOn: [
    worker
  ]
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: worker.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output backendUrl string = 'https://${backend.properties.configuration.ingress.fqdn}'
output frontendUrl string = 'https://${frontend.properties.configuration.ingress.fqdn}'
