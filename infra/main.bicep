@description('A short string representing the location, used in resource names to ensure uniqueness.')
param locationShort string

@description('Location for all resources.')
param location string

@description('The name of the app that you wish to create.')
param appnamePrefix string

@description('The name of the storage account.')
param storageAccountName string

@description('The pricing tier for the hosting plan.')
@allowed([
  'FC1'
  'EP1'
  'EP2'
  'EP3'
])
param hostingPlanSku string

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
    allowBlobPublicAccess: false // Keep blob public access disabled
    publicNetworkAccess: 'Enabled' // Enable network access for Function App
    networkAcls: {
      defaultAction: 'Allow' // Allow access from Azure services
      bypass: 'AzureServices' // Allow Azure services to bypass network rules
    }
  }
}

// Create 'deployments' blob container
resource deploymentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/deployments'
  properties: {
    publicAccess: 'None'
  }
}

var functionAppName = '${appnamePrefix}-${locationShort}-func'

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

var applicationInsightsname = '${appnamePrefix}-${locationShort}-insights'

// Create Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsname
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    DisableLocalAuth: false
  }
}

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

// Grant Function App managed identity Storage Blob Data Owner on the Storage Account
// Note: Role assignment removed to avoid deployment errors
// To enable managed identity for storage, manually assign "Storage Blob Data Owner" role
// to the function app's managed identity after deployment

// Note: Role assignment removed to avoid permission issues
// To enable managed identity for storage, manually assign "Storage Blob Data Owner" role
// to the function app's managed identity after deployment

// Create Logic App for email monitoring

@description('Shared mailbox address to monitor')
param sharedMailboxAddress string
// Logic App for email processing
var logicAppName = '${appnamePrefix}-${locationShort}-logic'
var office365ConnectionName = '${logicAppName}-office365-conn'
// Office 365 API connection
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: office365ConnectionName
  location: location
  properties: {
    displayName: 'Office 365 Outlook Connection for Claims Processing'
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
      displayName: 'Office 365 Outlook'
      description: 'Microsoft Office 365 is a cloud-based subscription service that brings together the best tools for the way people work today.'
      iconUri: 'https://connectoricons-prod.azureedge.net/releases/v1.0.1664/1.0.1664.3477/office365/icon.png'
      brandColor: '#0078d4'
    }
  }
}

resource stg 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: {
    displayName: logicAppName
    purpose: 'email-claims-processing'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        functionAppKey: {
          type: 'securestring'
          defaultValue: ''
        }
      }
      triggers: {
        When_a_new_email_arrives_in_shared_mailbox: {
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/SharedMailbox/Mail/OnNewEmail'
            queries: {
              mailboxAddress: sharedMailboxAddress
              folderPath: 'Inbox'
              includeAttachments: false
              onlyWithAttachment: false
              fetchOnlyWithAttachment: false
            }
          }
          splitOn: '@triggerBody()?[\'value\']'
        }
      }
      actions: {
        Extract_email_data: {
          runAfter: {}
          type: 'Compose'
          inputs: {
            sender: '@triggerBody()?[\'From\']'
            subject: '@triggerBody()?[\'Subject\']'
            bodyContent: '@coalesce(triggerBody()?[\'Body\'], triggerBody()?[\'BodyPreview\'], \'\')'
            attachments: '@triggerBody()?[\'Attachments\']'
          }
        }
        Process_email_body: {
          runAfter: {
            Extract_email_data: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: {
            cleanBodyText: '@replace(replace(replace(outputs(\'Extract_email_data\')[\'bodyContent\'], \'<[^>]*>\', \'\'), \'&nbsp;\', \' \'), \'&amp;\', \'&\')'
            processedAttachments: '@if(greater(length(coalesce(outputs(\'Extract_email_data\')[\'attachments\'], createArray())), 0), outputs(\'Extract_email_data\')[\'attachments\'], createArray())'
          }
        }
        Call_function_process_email: {
          runAfter: {
            Process_email_body: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${functionApp.properties.defaultHostName}/api/process_email'
            headers: {
              'Content-Type': 'application/json'
              'x-functions-key': '@parameters(\'functionAppKey\')'
            }
            body: {
              sender: '@outputs(\'Extract_email_data\')[\'sender\']'
              subject: '@outputs(\'Extract_email_data\')[\'subject\']'
              bodyText: '@outputs(\'Process_email_body\')[\'cleanBodyText\']'
              attachments: '@outputs(\'Process_email_body\')[\'processedAttachments\']'
            }
            retryPolicy: {
              type: 'fixed'
              count: 3
              interval: 'PT30S'
            }
          }
        }
        Handle_success_response: {
          runAfter: {
            Call_function_process_email: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: {
            status: 'success'
            message: 'Email processed successfully by Azure Function'
            functionResponse: '@body(\'Call_function_process_email\')'
            processedAt: '@utcNow()'
          }
        }
        Handle_function_error: {
          runAfter: {
            Call_function_process_email: [
              'Failed'
              'TimedOut'
            ]
          }
          type: 'Compose'
          inputs: {
            status: 'error'
            message: 'Failed to process email through Azure Function'
            error: '@body(\'Call_function_process_email\')'
            errorTime: '@utcNow()'
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
      functionAppKey: {
        value: listkeys(resourceId('Microsoft.Web/sites/host', functionAppName, 'default'), '2023-01-01').masterKey
      }
    }
  }
}

@description('The name of the SQL logical server.')
var server_name string = toLower('${appnamePrefix}-sqlsrv-${locationShort}')

@description('The name of the SQL Database.')
var sql_db_name string = toLower('${appnamePrefix}-sqldb-${locationShort}')


@description('The administrator username of the SQL logical server.')
param sqlAdminLogin string

@description('The administrator password of the SQL logical server.')
@secure()
param sqlAdminPassword string

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: server_name 
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
  }
}

resource sqlDB 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  parent: sqlServer
  name: sql_db_name
  location: location
  sku: {
    name: 'Basic'  
    tier: 'Basic'   
  }
}

@description('The name of the deployed function app.')
output functionAppName string = functionApp.name

@description('The resource ID of the deployed function app.')
output functionAppResourceId string = functionApp.id

@description('The default hostname (FQDN) of the deployed function app.')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The base URL (https) of the deployed function app.')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Application Insights connection string.')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The system-assigned managed identity principal ID.')
output managedIdentityPrincipalId string = functionApp.identity.principalId

@description('The name of the deployed logic app.')
output logicAppName string = stg.name

@description('The resource ID of the deployed logic app.')
output logicAppResourceId string = stg.id

@description('The Office 365 connection ID.')
output office365ConnectionId string = office365Connection.id

@description('The resource group name where resources are deployed.')
output resourceGroupName string = resourceGroup().name

@description('The location where resources are deployed.')
output location string = location

@description('The Logic App managed identity principal ID.')
output logicAppManagedIdentityPrincipalId string = stg.identity.principalId

@description('The SQL Server name.')
output sqlServerName string = sqlServer.name

// Storage Blob Data Contributor role definition ID
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// Grant Function App MSI Storage Blob Data Contributor on the storage account
resource functionAppBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId) // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
  }
}
