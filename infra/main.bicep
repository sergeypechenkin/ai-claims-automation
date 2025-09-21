@description('The name of the function app that you wish to create.')
param functionAppName string = 'ai-claims-automation'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The pricing tier for the hosting plan.')
@allowed([
  'FC1'
  'EP1'
  'EP2'
  'EP3'
])
param hostingPlanSku string = 'FC1'

@description('The name of the Application Insights.')
param applicationInsightsName string = '${functionAppName}-insights'

@description('The name of the storage account.')
param storageAccountName string = '${uniqueString(resourceGroup().id)}storage'

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

// Create Function App using Azure Verified Module
module functionApp 'br/public:avm/res/web/site:0.11.0' = {
  name: 'functionAppDeployment'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    serverFarmResourceId: hostingPlan.id
    
    // Storage account configuration
    storageAccountResourceId: storageAccount.id
    storageAccountUseIdentityAuthentication: true
    
    // Application Insights
    appInsightResourceId: applicationInsights.id
    
    // Security configurations
    httpsOnly: true
    managedIdentities: {
      systemAssigned: true
    }
    
    // Site configuration
    siteConfig: {
      pythonVersion: '3.12'
      linuxFxVersion: 'Python|3.12'
      alwaysOn: false // Not applicable for Flex Consumption
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      use32BitWorkerProcess: false
    }
    
    // App settings
    appSettingsKeyValuePairs: {
      AzureWebJobsStorage__accountName: storageAccount.name
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'python'
      WEBSITE_CONTENTSHARE: functionAppName
      SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
      ENABLE_ORYX_BUILD: 'true'
    }
  }
}

// Grant Storage Blob Data Owner role to the function app
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionAppName, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b') // Storage Blob Data Owner
    principalId: functionApp.outputs.systemAssignedMIPrincipalId
    principalType: 'ServicePrincipal'
  }
}

@description('The name of the deployed function app.')
output functionAppName string = functionApp.outputs.name

@description('The resource ID of the deployed function app.')
output functionAppResourceId string = functionApp.outputs.resourceId

@description('The default hostname of the deployed function app.')
output functionAppHostname string = functionApp.outputs.defaultHostname

@description('The Application Insights connection string.')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString