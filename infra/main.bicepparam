using './main.bicep'

// Required parameters
param functionAppName = 'func-ai-claims-automation'
param location = 'North Europe'

// Optional parameters - using defaults from template
param hostingPlanSku = 'FC1'
