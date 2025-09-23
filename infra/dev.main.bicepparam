using './main.bicep'

param functionAppName = 'func-ai-claims-dev'
param location = 'northeurope'
param hostingPlanSku = 'FC1'
param applicationInsightsName = 'func-ai-claims-ai-dev'
param storageAccountName = 'stclaimsdev001'
param logicAppName = 'logic-ai-claims-dev'
param sharedMailboxAddress = 'shared@maildomain.tld'

param appnamePrefix = 'aiclaims'
param locationShort = 'ne'

// SQL admin values are placeholders; real secrets supplied via CI/CD overrides
param SQLADMINLOGIN = 'override-in-ci'
param SQLADMINPASSWORD = 'Replace_This1!' // overridden by secure pipeline secret
