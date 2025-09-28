using './aih.bicep'

param hubName = 'dev-westus-001-aih'
param location = 'swedencentral'

param storageAccountName = 'staihdevswedencentral001'
param keyVaultName = 'kv-aih-dev-swedencentral-001'
param acrName = 'acraihdevswedencentral001'
param appInsightsName = 'appi-aih-dev-swedencentral-001'

param cogName = 'aoai-dev-swedencentral-001'
param cogKind = 'OpenAI'
param cogSkuName = 'S0'

param projectName = 'ai-claims-automation'
