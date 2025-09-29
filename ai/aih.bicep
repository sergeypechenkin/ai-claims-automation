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

// === Dependencies ===

// Storage
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  tags: tags
}

// Key Vault (RBAC mode)
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
    accessPolicies: [] // required by API, but empty
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

// === AI Hub ===
resource aihub 'Microsoft.MachineLearningServices/workspaces@2023-10-01' = {
  name: hubName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: hubName
    keyVault: kv.id
    applicationInsights: appi.id
    containerRegistry: acr.id
    storageAccount: storage.id
  }
}

// === Cognitive Services Account ===
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

// === Hub Project ===
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

// === Role Assignments ===
var roles = {
  storageBlobContributor: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  )
  acrPull: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  )
  kvSecretsUser: subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '4633458b-17de-408a-b874-0445c86b69e6'
  )
}

// Storage Blob Contributor
resource roleStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, roles.storageBlobContributor, aihub.name) // deterministic
  properties: {
    roleDefinitionId: roles.storageBlobContributor
    principalId: aihub.identity.principalId
  }
}

// ACR Pull
resource roleAcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, roles.acrPull, aihub.name)
  properties: {
    roleDefinitionId: roles.acrPull
    principalId: aihub.identity.principalId
  }
}

// KV Secrets User
resource roleKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, roles.kvSecretsUser, aihub.name)
  properties: {
    roleDefinitionId: roles.kvSecretsUser
    principalId: aihub.identity.principalId
  }
}

