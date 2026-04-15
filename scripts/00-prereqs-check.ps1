param(
    [string]$EnvFile = "./scripts/env.local"
)

. "$PSScriptRoot/common.ps1"

Write-Host "Checking local prerequisites..."

Require-Command -Name az
Require-Command -Name dotnet
Require-Command -Name ssh
Require-Command -Name scp

if (-not (Test-Path $EnvFile)) {
    throw "Missing $EnvFile. Copy scripts/env.sample to scripts/env.local and set required values."
}

Load-EnvFile -Path $EnvFile

if ([string]::IsNullOrWhiteSpace($env:SUBSCRIPTION_ID)) {
    throw "SUBSCRIPTION_ID is required in env.local"
}

if ([string]::IsNullOrWhiteSpace($env:TENANT_ID)) {
    throw "TENANT_ID is required in env.local"
}

az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI is not logged in. Run: az login"
}

az account set --subscription $env:SUBSCRIPTION_ID

Write-Host "Prerequisites check complete."
