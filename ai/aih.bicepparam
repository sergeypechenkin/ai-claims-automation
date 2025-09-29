using './aih.bicep'

param hubName = 'aih-dev-swc'
param location = 'swedencentral'

param storageAccountName = 'staihdevswc002'
param keyVaultName = 'kv-aih-dev-swc-002'
param acrName = 'acraihdevswc002'
param appInsightsName = 'appi-aih-dev-swc-002'

param cogName = 'aoai-dev-swc-002'
param cogKind = 'OpenAI'
param cogSkuName = 'S0'

param projectName = 'ai-claims-automation'
