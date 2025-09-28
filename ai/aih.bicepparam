using './aih.bicep'

param hubName = 'aih-dev-swc'
param location = 'swedencentral'

param storageAccountName = 'staihdevswc001'
param keyVaultName = 'kv-aih-dev-swc-001'
param acrName = 'acr-aih-dev-swc'
param appInsightsName = 'appi-aih-dev-swc-001'

param cogName = 'aoai-dev-swc-001'
param cogKind = 'OpenAI'
param cogSkuName = 'S0'

param projectName = 'ai-claims-automation'
