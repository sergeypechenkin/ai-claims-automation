@description('Name of the AI Hub (AML Workspace)')
param hubName string

@description('Location of the AI Hub and resources')
param location string = resourceGroup().location

@description('Resource tags')
param tags object = {}

@description('Name of the Storage Account (for AML default storage)')
param storageAccountName string

@description('Name of the Key Vault')
param keyVaultName string

@description('Name of the Container Registry')
param acrName string

@description('Name of the App Insights component')
param appInsightsName string

@description('Optional Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string = ''

@description('Name of the Cognitive Services account')
param cogName string
@description('Cognitive Services kind (e.g., OpenAI, Speech, Translator)')
@allowed([
  'OpenAI'
  'SpeechServices'
  'TextTranslation'
  'CustomVision'
])
param cogKind string = 'OpenAI'

@description('SKU for Cognitive Services (depends on kind)')
param cogSkuName string = 'S0'

@description('Name of the Hub Project (to attach Cognitive Services to)')
param projectName string = 'default-project'

// Storage
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  tags: tags
}

// Key Vault
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    enableRbacAuthorization: true
    accessPolicies: []
  }
  tags: tags
}

// Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
  tags: tags
}

// App Insights
resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: { Application_Type: 'web' }
  tags: tags
}

// AI Hub (AML Workspace)
resource aihub 'Microsoft.MachineLearningServices/workspaces@2023-10-01' = {
  name: hubName
  location: location
  tags: tags
  properties: {
    friendlyName: hubName
    keyVault: kv.id
    applicationInsights: appi.id
    containerRegistry: acr.id
    storageAccount: storage.id
  }
}

// Cognitive Services account (e.g., OpenAI)
resource cog 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: cogName
  location: location
  kind: cogKind
  sku: {
    name: cogSkuName
  }
  properties: {
    customSubDomainName: toLower(cogName)
  }
  tags: tags
}

// Hub Project
resource hubProject 'Microsoft.MachineLearningServices/workspaces/projects@2023-10-01' = {
  parent: aihub
  name: projectName
  properties: {
    description: 'AI Hub project connected to Cognitive Services'
    connectedResources: [
      {
        resourceId: cog.id
        type: 'CognitiveServices'
      }
    ]
  }
}
