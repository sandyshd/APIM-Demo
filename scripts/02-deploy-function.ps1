param(
    [string]$GeneratedEnvFile = "./scripts/.generated.env"
)

. "$PSScriptRoot/common.ps1"
Load-EnvFile -Path $GeneratedEnvFile

$publishDir = Join-Path $PSScriptRoot "../out/function"
$zipPath = Join-Path $PSScriptRoot "../out/function.zip"

if (Test-Path $publishDir) { Remove-Item -Recurse -Force $publishDir }
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

New-Item -ItemType Directory -Path $publishDir -Force | Out-Null

Write-Host "Publishing Function API..."
dotnet publish "$PSScriptRoot/../src/FunctionApi/FunctionApi.csproj" -c Release -o $publishDir

Compress-Archive -Path "$publishDir/*" -DestinationPath $zipPath -Force

Write-Host "Deploying Function API package..."
az functionapp deployment source config-zip `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:FUNCTION_APP `
  --src $zipPath `
  --output none

Write-Host "Function API deployed: https://$($env:FUNCTION_APP).azurewebsites.net/api/hello"
