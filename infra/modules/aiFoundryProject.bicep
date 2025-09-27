@description('Deployment location')
param location string

@description('Azure AI Project name')
param projectName string

// Derive hub name from project
var hubName = '${projectName}-hub'

resource aiHub 'Microsoft.AzureAI/hubs@2024-04-01-preview' = {
  name: hubName
  location: location
  properties: {
    displayName: hubName
    publicNetworkAccess: 'Enabled'
  }
}

resource aiProject 'Microsoft.AzureAI/projects@2024-04-01-preview' = {
  name: projectName
  location: location
  properties: {
    displayName: projectName
    hubResourceId: aiHub.id
  }
}

@description('Hub name')
output hubName string = aiHub.name

@description('Project name')
output projectName string = aiProject.name

@description('Project resource ID')
output projectId string = aiProject.id
