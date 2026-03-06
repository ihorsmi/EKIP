param location string
param searchServiceName string
param tags object

resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: 'standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    hostingMode: 'default'
    replicaCount: 1
    partitionCount: 1
  }
}

output searchId string = search.id
output searchName string = search.name
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output searchAdminKey string = listAdminKeys(search.id, search.apiVersion).primaryKey
