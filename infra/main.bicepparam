using './main.bicep'

param functionAppName = 'func-ai-claims-automation'
param location = 'North Europe'
param hostingPlanSku = 'FC1'
param applicationInsightsName = 'func-ai-claims-automation-insights'
param storageAccountName = 'staiclaimsauto001'
param logicAppName = 'logic-ai-claims-automation'

