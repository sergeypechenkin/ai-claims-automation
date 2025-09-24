using './main.bicep'

param appnamePrefix = 'ai-claims-automation'
param location = 'North Europe'
param locationShort = 'neu'
param hostingPlanSku = 'FC1'
param storageAccountName = 'staiclaimsauto001'
param sharedMailboxAddress = 'inbox@oopslab.in'
// SQL admin values are placeholders; real secrets supplied via CI/CD overrides
param sqlAdminLogin = 'override-in-ci'
param sqlAdminPassword = 'Replace_This1!' // overridden by secure pipeline secret

