param(
    [string]$EnvFile = "./scripts/env.local",
    [string]$GeneratedEnvFile = "./scripts/.generated.env"
)

. "$PSScriptRoot/common.ps1"

Load-EnvFile -Path $EnvFile

if (-not $env:LOCATION) { $env:LOCATION = "eastus" }
if (-not $env:NAME_PREFIX) { $env:NAME_PREFIX = "apim-demo" }
if (-not $env:UNIQUE_SUFFIX) {
    $env:UNIQUE_SUFFIX = -join ((97..122) + (48..57) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
}

$prefix = $env:NAME_PREFIX.ToLower()
$unique = $env:UNIQUE_SUFFIX.ToLower()
$base = "$prefix-$unique"
$storage = ("st" + ($prefix -replace "-", "") + $unique)
$storage = $storage.Substring(0, [Math]::Min(24, $storage.Length))

$names = @{
    RESOURCE_GROUP = "rg-$base"
    APP_INSIGHTS = "appi-$base"
    KEY_VAULT = "kv-$base"
    FUNCTION_APP = "func-$base"
    WEB_PLAN = "asp-$base"
    WEB_APP = "web-$base"
    APIM_NAME = "apim-$base"
    APIM_PRODUCT_ID = "demoproduct"
    APIM_SUBSCRIPTION_ID = "demo-sub"
    STORAGE_ACCOUNT = $storage
    ONPREM_VNET = "onprem-vnet-$unique"
    ONPREM_SUBNET = "onprem-subnet"
    ONPREM_NSG = "onprem-nsg-$unique"
    ONPREM_PIP = "onprem-pip-$unique"
    ONPREM_NIC = "onprem-nic-$unique"
    ONPREM_VM = "onprem-vm-$unique"
    ONPREM_ADMIN_USER = "azureuser"
}

$adminRoleId = "11111111-1111-1111-1111-111111111111"
$userRoleId = "22222222-2222-2222-2222-222222222222"

Write-Host "Using suffix: $unique"
az account set --subscription $env:SUBSCRIPTION_ID

az group create --name $names.RESOURCE_GROUP --location $env:LOCATION --output none

az monitor app-insights component create `
  --app $names.APP_INSIGHTS `
  --location $env:LOCATION `
  --resource-group $names.RESOURCE_GROUP `
  --application-type web `
  --output none

az storage account create `
  --name $names.STORAGE_ACCOUNT `
  --resource-group $names.RESOURCE_GROUP `
  --location $env:LOCATION `
  --sku Standard_LRS `
  --allow-blob-public-access false `
  --allow-shared-key-access true `
  --min-tls-version TLS1_2 `
  --output none

az appservice plan create `
  --name $names.WEB_PLAN `
  --resource-group $names.RESOURCE_GROUP `
  --location $env:LOCATION `
  --is-linux `
  --sku B1 `
  --output none

az functionapp create `
  --name $names.FUNCTION_APP `
  --resource-group $names.RESOURCE_GROUP `
  --plan $names.WEB_PLAN `
  --storage-account $names.STORAGE_ACCOUNT `
  --functions-version 4 `
  --runtime dotnet-isolated `
  --runtime-version 8 `
  --os-type Linux `
  --assign-identity [system] `
  --output none

# Assign RBAC roles on storage for Function App managed identity
$funcPrincipalId = az functionapp identity show --name $names.FUNCTION_APP --resource-group $names.RESOURCE_GROUP --query principalId -o tsv
$storageId = az storage account show --name $names.STORAGE_ACCOUNT --resource-group $names.RESOURCE_GROUP --query id -o tsv

az role assignment create --assignee-object-id $funcPrincipalId --assignee-principal-type ServicePrincipal --role "Storage Blob Data Owner" --scope $storageId --output none 2>$null
az role assignment create --assignee-object-id $funcPrincipalId --assignee-principal-type ServicePrincipal --role "Storage Account Contributor" --scope $storageId --output none 2>$null
az role assignment create --assignee-object-id $funcPrincipalId --assignee-principal-type ServicePrincipal --role "Storage Queue Data Contributor" --scope $storageId --output none 2>$null

# Switch to identity-based AzureWebJobsStorage
az functionapp config appsettings set --name $names.FUNCTION_APP --resource-group $names.RESOURCE_GROUP --settings "AzureWebJobsStorage__accountName=$($names.STORAGE_ACCOUNT)" --output none
az functionapp config appsettings delete --name $names.FUNCTION_APP --resource-group $names.RESOURCE_GROUP --setting-names AzureWebJobsStorage --output none 2>$null

az webapp create `
  --name $names.WEB_APP `
  --resource-group $names.RESOURCE_GROUP `
  --plan $names.WEB_PLAN `
  --runtime "DOTNETCORE:8.0" `
  --output none

az keyvault create `
  --name $names.KEY_VAULT `
  --resource-group $names.RESOURCE_GROUP `
  --location $env:LOCATION `
  --enable-rbac-authorization true `
  --output none

az apim create `
  --name $names.APIM_NAME `
  --resource-group $names.RESOURCE_GROUP `
  --location $env:LOCATION `
  --publisher-email $env:PUBLISHER_EMAIL `
  --publisher-name $env:PUBLISHER_NAME `
  --sku-name Developer `
  --output none

az apim update --name $names.APIM_NAME --resource-group $names.RESOURCE_GROUP --set identity.type=SystemAssigned --output none

$apimPrincipalId = az apim show --name $names.APIM_NAME --resource-group $names.RESOURCE_GROUP --query identity.principalId -o tsv
$kvId = az keyvault show --name $names.KEY_VAULT --resource-group $names.RESOURCE_GROUP --query id -o tsv
az role assignment create --assignee-object-id $apimPrincipalId --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope $kvId --output none 2>$null

# Also grant current user Key Vault admin so scripts can write secrets
$currentUserId = az ad signed-in-user show --query id -o tsv
az role assignment create --assignee-object-id $currentUserId --assignee-principal-type User --role "Key Vault Secrets Officer" --scope $kvId --output none 2>$null

$apiApp = az ad app create --display-name "$base-api" --sign-in-audience AzureADMyOrg --query appId -o tsv
$apiObjectId = az ad app show --id $apiApp --query id -o tsv

$rolesBody = @{
  identifierUris = @("api://$apiApp")
  appRoles = @(
    @{
      allowedMemberTypes = @("Application")
      description = "Admin access for APIM demo"
      displayName = "Admin"
      id = $adminRoleId
      isEnabled = $true
      origin = "Application"
      value = "Admin"
    },
    @{
      allowedMemberTypes = @("Application")
      description = "Reader access for APIM demo"
      displayName = "Reader"
      id = $userRoleId
      isEnabled = $true
      origin = "Application"
      value = "Reader"
    }
  )
} | ConvertTo-Json -Depth 5 -Compress

$rolesFile = Join-Path $env:TEMP "apim-demo-roles.json"
$rolesBody | Set-Content -Path $rolesFile -Encoding utf8
az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications/$apiObjectId" --headers "Content-Type=application/json" --body "@$rolesFile" --output none

az ad sp create --id $apiApp --output none

$adminClientApp = az ad app create --display-name "$base-client-admin" --sign-in-audience AzureADMyOrg --query appId -o tsv
$adminClientSecret = az ad app credential reset --id $adminClientApp --append --query password -o tsv
az ad sp create --id $adminClientApp --output none

$userClientApp = az ad app create --display-name "$base-client-user" --sign-in-audience AzureADMyOrg --query appId -o tsv
$userClientSecret = az ad app credential reset --id $userClientApp --append --query password -o tsv
az ad sp create --id $userClientApp --output none

$apiSpId = az ad sp show --id $apiApp --query id -o tsv
$adminSpId = az ad sp show --id $adminClientApp --query id -o tsv
$userSpId = az ad sp show --id $userClientApp --query id -o tsv

$adminAssignment = @{
  principalId = $adminSpId
  resourceId = $apiSpId
  appRoleId = $adminRoleId
} | ConvertTo-Json -Compress

$userAssignment = @{
  principalId = $userSpId
  resourceId = $apiSpId
  appRoleId = $userRoleId
} | ConvertTo-Json -Compress

$adminFile = Join-Path $env:TEMP "apim-demo-admin-assign.json"
$userFile = Join-Path $env:TEMP "apim-demo-user-assign.json"
$adminAssignment | Set-Content -Path $adminFile -Encoding utf8
$userAssignment | Set-Content -Path $userFile -Encoding utf8

az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$adminSpId/appRoleAssignments" --headers "Content-Type=application/json" --body "@$adminFile" --output none
az rest --method POST --url "https://graph.microsoft.com/v1.0/servicePrincipals/$userSpId/appRoleAssignments" --headers "Content-Type=application/json" --body "@$userFile" --output none

if ($adminClientSecret) {
  $adminSecFile = Join-Path $env:TEMP "apim-demo-admin-sec.txt"
  [System.IO.File]::WriteAllText($adminSecFile, $adminClientSecret)
  az keyvault secret set --vault-name $names.KEY_VAULT --name apim-client-admin-secret --file $adminSecFile --encoding utf-8 --output none
  Remove-Item $adminSecFile -ErrorAction SilentlyContinue
}
if ($userClientSecret) {
  $userSecFile = Join-Path $env:TEMP "apim-demo-user-sec.txt"
  [System.IO.File]::WriteAllText($userSecFile, $userClientSecret)
  az keyvault secret set --vault-name $names.KEY_VAULT --name apim-client-user-secret --file $userSecFile --encoding utf-8 --output none
  Remove-Item $userSecFile -ErrorAction SilentlyContinue
}

$appInsightsConnString = az monitor app-insights component show --app $names.APP_INSIGHTS --resource-group $names.RESOURCE_GROUP --query connectionString -o tsv

$generated = @{
    SUBSCRIPTION_ID = $env:SUBSCRIPTION_ID
    TENANT_ID = $env:TENANT_ID
    LOCATION = $env:LOCATION
    NAME_PREFIX = $prefix
    UNIQUE_SUFFIX = $unique
    RESOURCE_GROUP = $names.RESOURCE_GROUP
    APP_INSIGHTS = $names.APP_INSIGHTS
    APP_INSIGHTS_CONNECTION_STRING = $appInsightsConnString
    KEY_VAULT = $names.KEY_VAULT
    FUNCTION_APP = $names.FUNCTION_APP
    WEB_PLAN = $names.WEB_PLAN
    WEB_APP = $names.WEB_APP
    APIM_NAME = $names.APIM_NAME
    APIM_PRODUCT_ID = $names.APIM_PRODUCT_ID
    APIM_SUBSCRIPTION_ID = $names.APIM_SUBSCRIPTION_ID
    STORAGE_ACCOUNT = $names.STORAGE_ACCOUNT
    API_APP_ID = $apiApp
    API_AUDIENCE = "api://$apiApp"
    ADMIN_CLIENT_ID = $adminClientApp
    ADMIN_CLIENT_SECRET = $adminClientSecret
    USER_CLIENT_ID = $userClientApp
    USER_CLIENT_SECRET = $userClientSecret
    ADMIN_ROLE_ID = $adminRoleId
    USER_ROLE_ID = $userRoleId
    ALLOWED_ORIGIN = $(if ($env:ALLOWED_ORIGIN) { $env:ALLOWED_ORIGIN } else { "*" })
    ONPREM_VNET = $names.ONPREM_VNET
    ONPREM_SUBNET = $names.ONPREM_SUBNET
    ONPREM_NSG = $names.ONPREM_NSG
    ONPREM_PIP = $names.ONPREM_PIP
    ONPREM_NIC = $names.ONPREM_NIC
    ONPREM_VM = $names.ONPREM_VM
    ONPREM_ADMIN_USER = $names.ONPREM_ADMIN_USER
    SSH_PUBLIC_KEY_PATH = $env:SSH_PUBLIC_KEY_PATH
    SSH_PRIVATE_KEY_PATH = $env:SSH_PRIVATE_KEY_PATH
}

Save-GeneratedEnv -Path $GeneratedEnvFile -Values $generated
Write-Host "Provisioning complete. Output written to $GeneratedEnvFile"
