@description('A short string representing the location, used in resource names to ensure uniqueness.')
param locationShort string

@description('Location for all resources.')
param location string

@description('The name of the app that you wish to create.')
param appnamePrefix string

@description('The name of the storage account.')
param storageAccountName string

param gpt5_deployment string 
param gpt5_model string 
param gpt5_endpoint string 
param ai_services_endpoint string

// --- end added params ---

@description('The pricing tier for the hosting plan.')
@allowed([
  'FC1'
  'EP1'
  'EP2'
  'EP3'
])
param hostingPlanSku string

@description('Microsoft Teams Team ID where the adaptive card will be posted.')
param teamId string

@description('Microsoft Teams Channel ID (within the Team) where the adaptive card will be posted.')
param channelId string


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
    allowSharedKeyAccess: true  // Enable account key (shared key)
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

// ADD: emailmessages container required by Logic App (folderPath=emailmessages)
resource emailMessagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/emailmessages'
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
        // REPLACED: use full connection string (runtime needs this)
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_ACCOUNT_BLOB_ENDPOINT'
          value: storageAccount.properties.primaryEndpoints.blob
        }
        {
          name: 'AZURE_STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'EMAIL_ATTACHMENTS_CONTAINER'
          value: 'emailattachments'
        }
        {
          name: 'EMAIL_MESSAGES_CONTAINER'
          value: 'emailmessages'
        }
        {
          name: 'GPT5_DEPLOYMENT'
          value: gpt5_deployment
        }
        {
          name: 'GPT5_MODEL'
          value: gpt5_model
        }
        {
          name: 'GPT5_ENDPOINT'
          value: gpt5_endpoint
        }
        {
          name: 'AI_SERVICES_ENDPOINT'
          value: ai_services_endpoint
        }

        
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

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

// ADD: Grant Function App MSI Storage Blob Delegator (required for user delegation SAS)
resource functionAppBlobDelegator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageBlobDelegatorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDelegatorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ADD RBAC for Logic App managed identity to access blobs via MSI
resource logicAppBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, stg.name, storageBlobDataContributorRoleId) // Use stg.name instead of stg.identity.principalId
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: stg.identity.principalId
    principalType: 'ServicePrincipal'
  }
}


@description('Shared mailbox address to monitor')
param sharedMailboxAddress string
// Logic App for email processing
var logicAppName = '${appnamePrefix}-${locationShort}-logic-002'
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

var conversionServiceConnectionName = '${logicAppName}-conv-conn'

resource conversionserviceConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: conversionServiceConnectionName
  location: location
  properties: {
    displayName: 'Content Conversion Connection'
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'conversionservice')
      displayName: 'Content Conversion'
      description: 'Convert content between formats (HTML <-> Text, etc).'
    }
  }
}

var blobServiceEndpoint = string(storageAccount.properties.primaryEndpoints.blob)

resource stg 'Microsoft.Logic/workflows@2019-05-01' = {
  dependsOn: [
    functionApp  // ensure Function App (host key) exists before Logic App deployment
    azureblobConnection // ensure the connection is fully created first
  ]
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
          type: 'string'
        }
        // ADDED: expose team/channel IDs as workflow parameters (referenced by parameters('teamId'))
        teamId: {
          type: 'string'
        }
        channelId: {
          type: 'string'
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
              includeAttachments: true
              onlyWithAttachment: false
              fetchOnlyWithAttachment: false
            }
          }
          splitOn: '@triggerBody()?[\'value\']'
        }
      }
      actions: {
        // Call_function_process_email action moved to the correct location under actions
        Extract_email_data: {
          runAfter: {}
          type: 'Compose'
          inputs: {
            sender: '@triggerBody()?[\'From\']'
            subject: '@triggerBody()?[\'Subject\']'
            messageId: '@triggerBody()?[\'Id\']'
            bodyContent: '@coalesce(triggerBody()?[\'Body\'], triggerBody()?[\'BodyPreview\'], \'\')'
            attachments: '@coalesce(triggerBody()?[\'Attachments\'], createArray())'
          }
        }
        Html_to_text: {
          runAfter: { Extract_email_data: [ 'Succeeded' ] }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'conversionservice\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/html2text'
            body: {
              content: '@outputs(\'Extract_email_data\')[\'bodyContent\']'
              // optional parameters if supported:
              // inputType: 'html'
              // outputType: 'text'
            }
          }
        }
        Init_attachmentUris: {
          runAfter: { Html_to_text: [ 'Succeeded' ] }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'attachmentUris'
                type: 'Array'
                value: []
              }
            ]
          }
        }
        Init_emailBlobUri: {
          runAfter: { Init_attachmentUris: [ 'Succeeded' ] }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'emailBlobUri'
                type: 'String'
                value: ''
              }
            ]
          }
        }
        Upload_full_email: {
          runAfter: {
            Init_emailBlobUri: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'post'
            //https://learn.microsoft.com/en-us/connectors/azure-blob-connector/#connect-to-azure-blob-connector-using-blob-endpoint
            //path: '/v2/datasets/@{uriComponent(string(storageAccount.properties.primaryEndpoints.blob))}/files'
            //path: '/v2/datasets/@{encodeURIComponent(string(storageAccount.properties.primaryEndpoints.blob))}/files'
            //path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(string(storageAccount.properties.primaryEndpoints.blob)))}]/files'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${blobServiceEndpoint}\'))}/files'


            queries: {
              folderPath: 'emailmessages'
              name: '@concat(formatDateTime(utcNow(), \'yyyyMMddHHmmss\'), \'-message-\', coalesce(outputs(\'Extract_email_data\')[\'messageId\'], guid()), \'.msg\')'
              queryParametersSingleEncoded: true
            }
            body: '@string(outputs(\'Extract_email_data\'))' // store full JSON as text
          }
        }
        Set_email_blob_uri: {
          runAfter: {
            Upload_full_email: [
              'Succeeded'
            ]
          }
          type: 'SetVariable'
          inputs: {
            name: 'emailBlobUri'
            value: '@body(\'Upload_full_email\')?.path'
          }
        }
        For_each_attachments: {
          runAfter: {
            Set_email_blob_uri: [
              'Succeeded'
            ]
          }
          foreach: '@outputs(\'Extract_email_data\')[\'attachments\']'
          type: 'Foreach'
          actions: {
            If_valid_attachment: {
              // Changed function name lessOrEqual -> lessOrEquals
              expression: '@not(and(lessOrEquals(coalesce(item()?.Size, 0), 61440), contains(createArray(\'image/jpeg\', \'image/jpg\', \'image/png\', \'image/gif\'), toLower(coalesce(item()?.ContentType, \'\')))))'
              type: 'If'
              actions: {
                Upload_attachment_blob: {
                  runAfter: {}
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']' // fixed bracket
                      }
                    }
                    method: 'post'
                    path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${blobServiceEndpoint}\'))}/files'
                    queries: {
                      folderPath: 'emailattachments'
                      name: '@concat(formatDateTime(utcNow(), \'yyyyMMddHHmmss\'), \'_\', item()?[\'Name\'])'
                      queryParametersSingleEncoded: true
                    }
                    body: '@base64ToBinary(item()?[\'ContentBytes\'])'
                  }
                }
                Append_blob_uri: {
                  runAfter: {
                    Upload_attachment_blob: [
                      'Succeeded'
                    ]
                  }
                  type: 'AppendToArrayVariable'
                  inputs: {
                    name: 'attachmentUris'
                    value: '@body(\'Upload_attachment_blob\')?.path'
                  }
                }
              }
              else: {
                actions: {
                  // skipped small inline image
                }
              }
            }
          }
        }
        Call_function_process_email: {
          runAfter: {
            For_each_attachments: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${functionApp.properties.defaultHostName}/api/process_email?code=@{parameters(\'functionAppKey\')}'
            headers: {
              'Content-Type': 'application/json'
              // removed x-functions-key header; key now passed via query string
            }
            body: {
              sender: '@outputs(\'Extract_email_data\')[\'sender\']'
              subject: '@outputs(\'Extract_email_data\')[\'subject\']'
              bodyText: '@outputs(\'Html_to_text\')[\'body\']'
              timestamp: '@utcNow()'
              emailBlobUri: '@variables(\'emailBlobUri\')'
              attachmentUris: '@variables(\'attachmentUris\')'
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
Post_adaptive_card_to_teams: {
  runAfter: {
    Handle_success_response: [
      'Succeeded'
    ]
  }
  type: 'ApiConnection'
  inputs: {
    host: {
      connection: {
        name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
      }
    }
    method: 'post'
    path: '/beta/teams/@{encodeURIComponent(encodeURIComponent(parameters(\'teamId\')) )}/channels/@{encodeURIComponent(encodeURIComponent(parameters(\'channelId\')) )}/messages'
    body: {
      body: {
        contentType: 'html'
        content: '<p>Claims email processed successfully.</p><attachment id="1"></attachment>'
      }
      attachments: [
        {
          id: '1'
          contentType: 'application/vnd.microsoft.card.adaptive'
          content: '''
{
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "type": "AdaptiveCard",
  "version": "1.4",
  "body": [
    {
      "type": "TextBlock",
      "text": "Claims Email Processed",
      "weight": "Bolder",
      "size": "Medium"
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Sender:", "value": "@{outputs('Extract_email_data')?['sender']}" },
        { "title": "Subject:", "value": "@{outputs('Extract_email_data')?['subject']}" },
        { "title": "Attachments:", "value": "@{length(variables('attachmentUris'))}" },
        { "title": "Processed At (UTC):", "value": "@{utcNow()}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "Preview: @{substring(coalesce(body('Call_function_process_email')?['data']?['processedAttachments']?[0]?['extractedTextPreview'], '(no text)'), 0, min(180, length(coalesce(body('Call_function_process_email')?['data']?['processedAttachments']?[0]?['extractedTextPreview'], '(no text)'))))}",
      "wrap": true,
      "spacing": "Medium"
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "Open Function App",
      "url": "https://${functionApp.properties.defaultHostName}"
    }
  ]
}
'''
        }
      ]
    }
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
          azureblob: {
            connectionId: azureblobConnection.id
            connectionName: azureBlobConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
          }
          conversionservice: {
            connectionId: conversionserviceConnection.id
            connectionName: conversionServiceConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'conversionservice')
          }
          teams: {
            connectionId: teamsConnection.id
            connectionName: teamsConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
          }
        }
      }
      functionAppKey: {
        // Use default host function key (more stable) with correct API version
        value: listKeys(resourceId('Microsoft.Web/sites/host', functionAppName, 'default'), '2022-09-01').functionKeys.default
      }
      // ADDED: bind workflow parameters to template parameters
      teamId: {
        value: teamId
      }
      channelId: {
        value: channelId
      }
    }
  }
}

// Container for attachments
resource emailAttachmentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/emailattachments'
  properties: {
    publicAccess: 'None'
  }
}


var azureBlobConnectionName = '${logicAppName}-blob-conn-${storageAccountName}-v4'
resource azureblobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: azureBlobConnectionName
  location: location
  properties: {
    displayName: 'Blob Storage Connection-Keys'
    parameterValues: {
      accountName: storageAccount.properties.primaryEndpoints.blob
      accessKey: storageAccount.listKeys().keys[0].value
    }
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
  }
  dependsOn: [
    storageAccount
    emailMessagesContainer
    emailAttachmentsContainer
  ]
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
    publicNetworkAccess: 'Enabled' // Enable public network access
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

// Allow Azure services to access the SQL server
resource sqlServerFirewallRuleAzure 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
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

// ADD: Storage Blob Delegator role definition ID (verify this GUID; replace if your tenant differs)
var storageBlobDelegatorRoleId = 'db58b8e5-c6ad-4a2a-8342-4190687cbf4a'


var teamsConnectionName = '${logicAppName}-teams-conn'

// Teams connector connection (authorization will be granted interactively by sergeype@microsoft.com post-deployment)
resource teamsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: teamsConnectionName
  location: location
  properties: {
    displayName: 'Teams Connection (sergeype@microsoft.com)'
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')
      displayName: 'Microsoft Teams'
      description: 'Microsoft Teams is a chat-based workspace in Office 365.'
    }
  }
}

