param(
    [string]$GeneratedEnvFile = "./scripts/.generated.env"
)

. "$PSScriptRoot/common.ps1"
Load-EnvFile -Path $GeneratedEnvFile

# Get APIM managed identity object ID for backend trust
$apimPrincipalId = az apim show --name $env:APIM_NAME --resource-group $env:RESOURCE_GROUP --query identity.principalId -o tsv

$publishDir = Join-Path $PSScriptRoot "../out/webapi"
$zipPath = Join-Path $PSScriptRoot "../out/webapi.zip"

if (Test-Path $publishDir) { Remove-Item -Recurse -Force $publishDir }
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

New-Item -ItemType Directory -Path $publishDir -Force | Out-Null

Write-Host "Publishing Web API..."
dotnet publish "$PSScriptRoot/../src/WebApi/WebApi.csproj" -c Release -o $publishDir

Compress-Archive -Path "$publishDir/*" -DestinationPath $zipPath -Force

Write-Host "Deploying Web API package..."
az webapp deploy `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:WEB_APP `
  --src-path $zipPath `
  --type zip `
  --output none

Write-Host "Setting Web API Entra ID authentication settings..."
az webapp config appsettings set `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:WEB_APP `
  --settings "AzureAd__Instance=https://login.microsoftonline.com/" "AzureAd__TenantId=$($env:TENANT_ID)" "AzureAd__ClientId=$($env:API_APP_ID)" "AzureAd__Audience=api://$($env:API_APP_ID)" "ApimManagedIdentityObjectId=$apimPrincipalId" `
  --output none

Write-Host "Web API deployed: https://$($env:WEB_APP).azurewebsites.net/swagger/v1/swagger.json"
