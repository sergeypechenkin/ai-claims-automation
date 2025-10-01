using './aih.bicep'

param hubName = 'aih-dev-swc'
param location = 'swedencentral'

param storageAccountName = 'staihdevswc003'
param keyVaultName = 'kv-aih-dev-swc-003'
param acrName = 'acraihdevswc003'
param appInsightsName = 'appi-aih-dev-swc-003'

param cogName = 'aoai-dev-swc-003'
param cogKind = 'OpenAI'
param cogSkuName = 'S0'

param projectName = 'ai-claims-automation'
