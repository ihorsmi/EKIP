param location string
param openAiAccountName string
param tags object

@description('Deploy common model deployments (gpt-4o + text-embedding-3-large). Requires region/model availability.')
param deployModels bool = false

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiAccountName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployModels) {
  name: 'gpt-4o'
  parent: openai
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
  }
}

resource embedDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = if (deployModels) {
  name: 'text-embedding-3-large'
  parent: openai
  sku: {
    name: 'GlobalStandard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
  }
}

output openAiId string = openai.id
output openAiName string = openai.name
output openAiEndpoint string = openai.properties.endpoint
