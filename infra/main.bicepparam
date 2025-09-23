using './main.bicep'

param appnamePrefix = 'ai-claims-automation'
param location = 'North Europe'
param locationShort = 'neu'
param functionAppName = '${appnamePrefix}-${locationShort}-func'
param hostingPlanSku = 'FC1'
param applicationInsightsName = '${appnamePrefix}-${locationShort}-insights'
param storageAccountName = 'staiclaimsauto001'
param logicAppName = '${appnamePrefix}-${locationShort}-logic'
param sharedMailboxAddress = 'inbox@oopslab.in'

