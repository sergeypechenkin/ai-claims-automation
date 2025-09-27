@description('Deployment location')
param location string

@description('Azure AI Hub name')
param hubName string

@description('Azure AI Project name')
param projectName string

@description('Tags to apply to all resources')
param resourceTags object = {}

@description('Public network access setting for the Hub')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

// Hub
resource aiHub 'Microsoft.AzureAI/hubs@2024-04-01-preview' = {
  name: hubName
  location: location
  tags: resourceTags
  properties: {
    displayName: hubName
    publicNetworkAccess: publicNetworkAccess
  }
}

// Project
resource aiProject 'Microsoft.AzureAI/projects@2024-04-01-preview' = {
  name: projectName
  location: location
  tags: resourceTags
  properties: {
    displayName: projectName
    hubResourceId: aiHub.id
  }
}

@description('AI Hub name')
output hubName string = aiHub.name

@description('AI Hub resource ID')
output hubId string = aiHub.id

@description('AI Project name')
output projectName string = aiProject.name

@description('AI Project resource ID')
output projectId string = aiProject.id
