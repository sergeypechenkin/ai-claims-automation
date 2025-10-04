# Activate virtual environment and start Azure Functions
# This script ensures the function runtime uses the correct Python environment

Write-Host "🚀 Starting Azure Functions with Virtual Environment..." -ForegroundColor Green

# Activate the virtual environment
$venvPath = ".\.venv\Scripts\Activate.ps1"
if (Test-Path $venvPath) {
    & $venvPath
    Write-Host "✅ Virtual environment activated" -ForegroundColor Green
} else {
    Write-Host "❌ Virtual environment not found at $venvPath" -ForegroundColor Red
    exit 1
}

# Set environment variables for Azure Functions
$env:FUNCTIONS_WORKER_RUNTIME = "python"
$env:PYTHONPATH = "$PWD;$PWD\.venv\Lib\site-packages"

# Verify Python and packages
Write-Host "🔍 Checking Python environment..." -ForegroundColor Yellow
python --version
python -c "import sys; print('Python path:', sys.path[:3])"

# Test import of required modules
Write-Host "🔍 Testing package imports..." -ForegroundColor Yellow
python -c "import requests; print('✅ requests imported successfully')"
python -c "import azure.functions; print('✅ azure-functions imported successfully')"

# Start Azure Functions
Write-Host "🎯 Starting Azure Functions host..." -ForegroundColor Green
func host start --verbose

