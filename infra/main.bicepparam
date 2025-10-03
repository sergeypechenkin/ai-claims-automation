using './main.bicep'

param appnamePrefix = 'ai-claims-automation'
param location = 'North Europe'
param locationShort = 'neu'
param hostingPlanSku = 'FC1'
param storageAccountName = 'staiclaimsauto001'
param sharedMailboxAddress = 'inbox@oopslab.in'
// SQL admin values are placeholders; real secrets supplied via CI/CD overrides
param sqlAdminLogin = 'override-in-ci'
param sqlAdminPassword = 'Replace_This1!' // overridden by secure pipeline secretparam
param channelId = '19:bGHdGdh4ymF0kNwu1XY7OYoq8Rap4pv8X2x6y9aYIKw1@thread.tacv2'
param teamId = 'be10bf38-a53e-463c-b3d2-66a38ea12e55'
param gpt5_deployment = 'override-in-ci'
param gpt5_model = 'override-in-ci'
param gpt5_endpoint = 'override-in-ci'
param ai_services_endpoint = 'override-in-ci'
