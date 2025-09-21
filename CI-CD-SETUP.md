# Azure Functions CI/CD Deployment Guide

This guide provides comprehensive instructions for setting up CI/CD for your Azure Functions Python application using both GitHub Actions and Azure DevOps.

## Table of Contents

- [Prerequisites](#prerequisites)
- [GitHub Actions Setup](#github-actions-setup)
- [Azure DevOps Setup](#azure-devops-setup)
- [Infrastructure as Code](#infrastructure-as-code)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Prerequisites

1. **Azure Subscription** with sufficient permissions
2. **Azure CLI** installed locally
3. **Git repository** (GitHub or Azure DevOps)
4. **Python 3.12** runtime

## GitHub Actions Setup

### 1. Authentication Setup

#### Option A: Service Principal (Recommended)

Create a service principal for authentication:

```bash
# Create service principal
az ad sp create-for-rbac --name "ai-claims-automation-sp" --role contributor --scopes /subscriptions/YOUR_SUBSCRIPTION_ID

Add the output as a GitHub secret named `AZURE_CREDENTIALS`.


### 2. GitHub Secrets Configuration

Add these secrets to your GitHub repository:

- `AZURE_CREDENTIALS`: Service principal JSON (if using SP auth)
- `AZURE_CLIENT_ID`: Client ID (if using OIDC)
- `AZURE_TENANT_ID`: Tenant ID (if using OIDC)
- `AZURE_SUBSCRIPTION_ID`: Subscription ID (if using OIDC)

### 3. Workflow Customization

Update the workflow file (`.github/workflows/deploy.yml`) with your specific values:

```yaml
env:
  AZURE_FUNCTIONAPP_NAME: 'your-unique-function-app-name'
  AZURE_RESOURCE_GROUP: 'your-resource-group-name'
  AZURE_LOCATION: 'East US'  # Or your preferred region
```

## Azure DevOps Setup

### 1. Service Connection

1. Go to **Project Settings** > **Service connections**
2. Create **New service connection** > **Azure Resource Manager**
3. Choose **Service principal (automatic)** or **Service principal (manual)**
4. Configure with appropriate permissions

### 2. Variable Groups

Create a variable group with these variables:

- `azureSubscription`: Name of your service connection
- `functionAppName`: Your function app name
- `resourceGroupName`: Your resource group name
- `pythonVersion`: `3.12`

### 3. Pipeline Setup

Use the provided `azure-pipelines.yml` file and update the variables section:

```yaml
variables:
  azureSubscription: 'your-service-connection-name'
  functionAppName: 'your-function-app-name'
  vmImageName: 'ubuntu-latest'
  pythonVersion: '3.12'
```

## Infrastructure as Code

### Bicep Template Features

The provided Bicep template (`infra/main.bicep`) includes:

- **Flex Consumption Plan** (FC1) for optimal cost and performance
- **Linux-based Function App** (required for Python)
- **Application Insights** for monitoring
- **Storage Account** with managed identity authentication
- **Security configurations** (HTTPS only, minimal TLS 1.2)
- **Azure Verified Modules** for best practices

### Deployment Commands

#### Local Deployment
```bash
# Create resource group
az group create --name rg-ai-claims-automation --location "East US"

# Deploy infrastructure
az deployment group create \
  --resource-group rg-ai-claims-automation \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

#### CI/CD Deployment
The GitHub Actions workflow automatically deploys infrastructure before deploying the application code.

## Security Best Practices

### 1. Authentication & Authorization
- ✅ Use **System-Assigned Managed Identity**
- ✅ Disable **basic publishing credentials** (FTP/SCM)
- ✅ Enable **HTTPS only**
- ✅ Use **minimum TLS 1.2**

### 2. Network Security
- Consider **Private Endpoints** for production
- Use **VNet integration** if needed
- Configure **IP restrictions** as required

### 3. Application Security
- Store secrets in **Azure Key Vault**
- Use **Application Insights** for monitoring
- Enable **diagnostic logging**

### 4. CI/CD Security
- Use **least-privilege service principals**
- Rotate **service principal credentials** regularly
- Use **environment-specific secrets**

## Application Configuration

### Required Environment Variables

The deployment automatically configures these app settings:

```bash
FUNCTIONS_WORKER_RUNTIME=python
FUNCTIONS_EXTENSION_VERSION=~4
AzureWebJobsStorage__accountName=[storage-account-name]
APPINSIGHTS_INSTRUMENTATIONKEY=[app-insights-key]
APPLICATIONINSIGHTS_CONNECTION_STRING=[connection-string]
SCM_DO_BUILD_DURING_DEPLOYMENT=true
ENABLE_ORYX_BUILD=true
```

### Custom Application Settings

Add additional settings in the Bicep template:

```bicep
appSettingsKeyValuePairs: {
  // Existing settings...
  CUSTOM_SETTING: 'value'
  API_ENDPOINT: 'https://api.example.com'
}
```

## Monitoring & Troubleshooting

### Application Insights Queries

Monitor your function app with these KQL queries:

```kusto
// Function execution count
requests
| where cloud_RoleName == "your-function-app-name"
| summarize count() by bin(timestamp, 1h)

// Error rates
traces
| where severityLevel >= 3
| where cloud_RoleName == "your-function-app-name"
| summarize errors = count() by bin(timestamp, 1h)
```

### Common Issues

1. **Deployment Failures**
   - Check service principal permissions
   - Verify resource group exists
   - Review Activity Log in Azure Portal

2. **Function Not Starting**
   - Check Application Insights logs
   - Verify Python version compatibility
   - Review app settings configuration

3. **Authentication Issues**
   - Validate service principal credentials
   - Check Azure RBAC assignments
   - Verify subscription access

### Debugging Commands

```bash
# Check function app status
az functionapp show --name your-function-app-name --resource-group your-rg

# View application logs
az functionapp log tail --name your-function-app-name --resource-group your-rg

# Get function app configuration
az functionapp config appsettings list --name your-function-app-name --resource-group your-rg
```

## Advanced Configuration

### Slot Deployment
For production scenarios, consider using deployment slots:

```bash
# Create staging slot
az functionapp deployment slot create \
  --name your-function-app \
  --resource-group your-rg \
  --slot staging

# Deploy to staging
az functionapp deployment source config-zip \
  --src your-code.zip \
  --name your-function-app \
  --resource-group your-rg \
  --slot staging

# Swap slots
az functionapp deployment slot swap \
  --name your-function-app \
  --resource-group your-rg \
  --slot staging \
  --target-slot production
```

### Scaling Configuration
Configure auto-scaling for production workloads:

```bicep
functionAppConfig: {
  scaleAndConcurrency: {
    maximumInstanceCount: 200
    instanceMemoryMB: 4096
  }
}
```

## Cost Optimization

1. Use **Flex Consumption** for variable workloads
2. Configure **appropriate instance memory**
3. Set **maximum instance count** limits
4. Monitor costs with **Azure Cost Management**

## Next Steps

1. **Set up monitoring** with Application Insights dashboards
2. **Configure alerts** for errors and performance
3. **Implement health checks** in your functions
4. **Set up backup** and disaster recovery
5. **Document** your specific business logic and APIs

This CI/CD setup provides a robust foundation for deploying and managing your Azure Functions application with industry best practices for security, monitoring, and maintainability.