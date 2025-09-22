@description('The name of the function app that you wish to create.')
param functionAppName string

@description('Location for all resources.')
param location string

@description('The pricing tier for the hosting plan.')
@allowed([
  'FC1'
  'EP1'
  'EP2'
  'EP3'
])
param hostingPlanSku string

@description('The name of the Application Insights.')
param applicationInsightsName string

@description('The name of the storage account.')
param storageAccountName string

// Create storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false // Disable key-based access for security
  }
}

// Create hosting plan (Flex Consumption)
resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: hostingPlanSku
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true // Linux
  }
}

// Create Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// Create Function App directly instead of using AVM module
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deployments'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
    }
    siteConfig: {
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}


// Note: Role assignment removed to avoid permission issues
// To enable managed identity for storage, manually assign "Storage Blob Data Owner" role
// to the function app's managed identity after deployment

@description('The name of the deployed function app.')
output functionAppName string = functionApp.name

@description('The resource ID of the deployed function app.')
output functionAppResourceId string = functionApp.id

@description('The default hostname of the deployed function app.')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The Application Insights connection string.')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The system-assigned managed identity principal ID.')
output managedIdentityPrincipalId string = functionApp.identity.principalId

