param location string
param storageAccountName string
param keyVaultName string
param acrName string
param tags object

var storageNameClean = replace(storageAccountName, '-', '')
var acrNameClean = replace(acrName, '-', '')

resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageNameClean
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: '${storage.name}/default'
}

resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${storage.name}/default/documents'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [blobService]
}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    sku: {
      family: 'A'
      name: 'standard'
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrNameClean
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

output storageAccountId string = storage.id
output storageAccountName string = storage.name
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output acrId string = acr.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
