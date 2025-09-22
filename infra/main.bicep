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

// Create Logic App for email monitoring
@description('The name of the logic app to create.')
param logicAppName string

@description('Email address to monitor for incoming claims')
param targetEmailAddress string

@description('Office 365 connection name')
param office365ConnectionName string = '${logicAppName}-office365-conn'

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

// Logic App for email processing
resource stg 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  dependsOn: [
    functionApp
  ]
  tags: {
    displayName: logicAppName
    purpose: 'email-claims-processing'
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
      }
      triggers: {
        When_a_new_email_arrives: {
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
            path: '/Mail/OnNewEmail'
            queries: {
              folderPath: 'Inbox'
              to: targetEmailAddress
              subjectFilter: 'claim,insurance,damage,accident,injury,incident'
              includeAttachments: false
              onlyWithAttachment: false
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
            received: '@triggerBody()?[\'DateTimeReceived\']'
            messageId: '@triggerBody()?[\'Id\']'
            hasAttachments: '@triggerBody()?[\'HasAttachment\']'
            body: '@triggerBody()?[\'Body\']'
          }
        }
        Log_email_received: {
          runAfter: {
            Extract_email_data: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: {
            message: 'New email received from @{outputs(\'Extract_email_data\')[\'sender\']} with subject: @{outputs(\'Extract_email_data\')[\'subject\']}'
            timestamp: '@utcNow()'
            logicAppName: logicAppName
          }
        }
        Call_function_process_email: {
          runAfter: {
            Log_email_received: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://@{reference(resourceId(\'Microsoft.Web/sites\', \'${functionAppName}\')).defaultHostName}/api/process_email'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              sender: '@outputs(\'Extract_email_data\')[\'sender\']'
              subject: '@outputs(\'Extract_email_data\')[\'subject\']'
              received: '@outputs(\'Extract_email_data\')[\'received\']'
              messageId: '@outputs(\'Extract_email_data\')[\'messageId\']'
              hasAttachments: '@outputs(\'Extract_email_data\')[\'hasAttachments\']'
              source: 'logic-app'
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
            emailSender: '@outputs(\'Extract_email_data\')[\'sender\']'
            emailSubject: '@outputs(\'Extract_email_data\')[\'subject\']'
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
            errorCode: '@outputs(\'Call_function_process_email\')[\'statusCode\']'
            emailData: '@outputs(\'Extract_email_data\')'
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
    }
  }
}


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
