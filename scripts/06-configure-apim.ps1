param(
    [string]$GeneratedEnvFile = "./scripts/.generated.env"
)

. "$PSScriptRoot/common.ps1"
Load-EnvFile -Path $GeneratedEnvFile

$functionOpenApi = Join-Path $PSScriptRoot "../apim/openapi/function-api.json"
$webOpenApiV1 = Join-Path $PSScriptRoot "../apim/openapi/web-api-v1.json"
$webOpenApiV2 = Join-Path $PSScriptRoot "../apim/openapi/web-api-v2.json"
$legacyOpenApi = Join-Path $PSScriptRoot "../apim/openapi/legacy-api.json"

$globalPolicyPath = Join-Path $PSScriptRoot "../apim/policies/global.xml"
$functionPolicyPath = Join-Path $PSScriptRoot "../apim/policies/function-api.xml"
$webPolicyPath = Join-Path $PSScriptRoot "../apim/policies/web-api.xml"
$legacyPolicyPath = Join-Path $PSScriptRoot "../apim/policies/legacy-api.xml"
$adminPolicyPath = Join-Path $PSScriptRoot "../apim/policies/web-api-admin-operation.xml"
$functionRev2PolicyPath = Join-Path $PSScriptRoot "../apim/policies/function-api-rev2.xml"

$functionBackendUrl = "https://$($env:FUNCTION_APP).azurewebsites.net/api"
$webBackendUrl = "https://$($env:WEB_APP).azurewebsites.net"
$legacyBackendUrl = "http://$($env:ONPREM_VM_PUBLIC_IP):5000/legacy"

$apiVersion = "2022-08-01"
$apimBase = "/subscriptions/$($env:SUBSCRIPTION_ID)/resourceGroups/$($env:RESOURCE_GROUP)/providers/Microsoft.ApiManagement/service/$($env:APIM_NAME)"

# Helper: PUT a resource via ARM REST API using a temp JSON file
function Put-ApimResource {
    param([string]$Path, [hashtable]$Body)
    $url = "https://management.azure.com${apimBase}/${Path}?api-version=$apiVersion"
    $tmpFile = [System.IO.Path]::GetTempFileName()
    $Body | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $tmpFile -Encoding utf8NoBOM
    az rest --method put --url $url --body "@$tmpFile" --headers "Content-Type=application/json" --output none 2>&1
    Remove-Item -Force $tmpFile -ErrorAction SilentlyContinue
}

# ─── Named Values ────────────────────────────────────────────────────────────
Write-Host "Creating APIM Named Values..."
$namedValues = @(
    @{ id = "aad-tenant-id";       displayName = "aad-tenant-id";       value = $env:TENANT_ID },
    @{ id = "aad-audience";        displayName = "aad-audience";        value = $env:API_AUDIENCE },
    @{ id = "allowed-origin";      displayName = "allowed-origin";      value = $env:ALLOWED_ORIGIN },
    @{ id = "web-backend-url";     displayName = "web-backend-url";     value = $webBackendUrl },
    @{ id = "legacy-backend-url";  displayName = "legacy-backend-url";  value = $legacyBackendUrl }
)

foreach ($nv in $namedValues) {
    az apim nv create --resource-group $env:RESOURCE_GROUP --service-name $env:APIM_NAME `
      --named-value-id $nv.id --display-name $nv.displayName --value $nv.value --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        az apim nv update --resource-group $env:RESOURCE_GROUP --service-name $env:APIM_NAME `
          --named-value-id $nv.id --value $nv.value --output none 2>$null
    }
}

# Key Vault referenced named value (requires REST API)
$kvSecretId = "https://$($env:KEY_VAULT).vault.azure.net/secrets/apim-client-admin-secret"
Put-ApimResource -Path "namedValues/kv-admin-client-secret" -Body @{
    properties = @{
        displayName = "kv-admin-client-secret"
        secret      = $true
        keyVault    = @{ secretIdentifier = $kvSecretId }
    }
}

# ─── Product ─────────────────────────────────────────────────────────────────
Write-Host "Creating APIM product..."
az apim product create `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIM_NAME `
  --product-id $env:APIM_PRODUCT_ID `
  --product-name "DemoProduct" `
  --description "Product for APIM demo APIs" `
  --subscription-required true `
  --approval-required false `
  --subscriptions-limit 100 `
  --state published `
  --output none

# ─── Import APIs ─────────────────────────────────────────────────────────────
Write-Host "Importing Function API..."
az apim api import `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIM_NAME `
  --path function `
  --api-id function-api `
  --display-name "function-api" `
  --specification-format OpenApiJson `
  --specification-path $functionOpenApi `
  --service-url $functionBackendUrl `
  --subscription-required true `
  --output none

Write-Host "Creating Web API version set..."
Put-ApimResource -Path "apiVersionSets/web-api-versions" -Body @{
    properties = @{
        displayName      = "Web API"
        versioningScheme = "Segment"
    }
}

Write-Host "Importing Web API v1..."
$webV1Spec = Get-Content $webOpenApiV1 -Raw
Put-ApimResource -Path "apis/web-api" -Body @{
    properties = @{
        displayName     = "Web API"
        path            = "web"
        apiVersion      = "v1"
        apiVersionSetId = "${apimBase}/apiVersionSets/web-api-versions"
        serviceUrl      = $webBackendUrl
        protocols       = @("https")
        subscriptionRequired = $true
        format          = "openapi+json"
        value           = $webV1Spec
    }
}

Write-Host "Importing Web API v2..."
$webV2Spec = Get-Content $webOpenApiV2 -Raw
Put-ApimResource -Path "apis/web-api-v2" -Body @{
    properties = @{
        displayName     = "Web API"
        path            = "web"
        apiVersion      = "v2"
        apiVersionSetId = "${apimBase}/apiVersionSets/web-api-versions"
        serviceUrl      = "$webBackendUrl/v2"
        protocols       = @("https")
        subscriptionRequired = $true
        format          = "openapi+json"
        value           = $webV2Spec
    }
}

Write-Host "Importing Legacy API..."
az apim api import `
  --resource-group $env:RESOURCE_GROUP `
  --service-name $env:APIM_NAME `
  --path legacy `
  --api-id legacy-api `
  --display-name "legacy-api" `
  --specification-format OpenApiJson `
  --specification-path $legacyOpenApi `
  --service-url $legacyBackendUrl `
  --subscription-required true `
  --output none

# ─── Add APIs to Product ─────────────────────────────────────────────────────
Write-Host "Adding APIs to product..."
foreach ($apiId in @("function-api", "web-api", "web-api-v2", "legacy-api")) {
    az apim product api add --resource-group $env:RESOURCE_GROUP --service-name $env:APIM_NAME --product-id $env:APIM_PRODUCT_ID --api-id $apiId --output none 2>$null
}

# ─── Subscription (REST API) ─────────────────────────────────────────────────
Write-Host "Creating APIM subscription for DemoProduct..."
Put-ApimResource -Path "subscriptions/$($env:APIM_SUBSCRIPTION_ID)" -Body @{
    properties = @{
        scope       = "${apimBase}/products/$($env:APIM_PRODUCT_ID)"
        displayName = "Demo Subscription"
        state       = "active"
        allowTracing = $true
    }
}

# ─── Policies (REST API) ─────────────────────────────────────────────────────
Write-Host "Applying policies..."
$globalPolicy = Get-Content $globalPolicyPath -Raw
$functionPolicy = Get-Content $functionPolicyPath -Raw
$webPolicy = Get-Content $webPolicyPath -Raw
$legacyPolicy = Get-Content $legacyPolicyPath -Raw
$adminPolicy = Get-Content $adminPolicyPath -Raw

# Global policy
Put-ApimResource -Path "policies/policy" -Body @{ properties = @{ value = $globalPolicy; format = "rawxml" } }

# API-level policies
$apiPolicies = @{
    "function-api" = $functionPolicy
    "web-api"      = $webPolicy
    "web-api-v2"   = $webPolicy
    "legacy-api"   = $legacyPolicy
}
foreach ($entry in $apiPolicies.GetEnumerator()) {
    Put-ApimResource -Path "apis/$($entry.Key)/policies/policy" -Body @{ properties = @{ value = $entry.Value; format = "rawxml" } }
}

# Operation-level policy for admin health
Put-ApimResource -Path "apis/web-api/operations/getAdminHealth/policies/policy" -Body @{ properties = @{ value = $adminPolicy; format = "rawxml" } }

# ─── Revisions (non-breaking changes) ────────────────────────────────────────
Write-Host "Creating Function API revision 2 (adds outbound headers)..."
$functionRev2Policy = Get-Content $functionRev2PolicyPath -Raw
$functionSpec = Get-Content $functionOpenApi -Raw

# Create revision 2 of Function API with operations from OpenAPI spec
Put-ApimResource -Path "apis/function-api;rev=2" -Body @{
    properties = @{
        displayName            = "function-api"
        path                   = "function"
        serviceUrl             = $functionBackendUrl
        protocols              = @("https")
        subscriptionRequired   = $true
        apiRevisionDescription = "Added x-api-revision and x-request-timestamp outbound headers"
        format                 = "openapi+json"
        value                  = $functionSpec
    }
}

# Apply rev2 policy
Put-ApimResource -Path "apis/function-api;rev=2/policies/policy" -Body @{ properties = @{ value = $functionRev2Policy; format = "rawxml" } }

# ─── App Insights Diagnostics (REST API) ─────────────────────────────────────
Write-Host "Configuring APIM diagnostics to Application Insights..."
try {
    $appInsightsId = az monitor app-insights component show --app $env:APP_INSIGHTS --resource-group $env:RESOURCE_GROUP --query id -o tsv 2>$null
    $instrumentationKey = az monitor app-insights component show --app $env:APP_INSIGHTS --resource-group $env:RESOURCE_GROUP --query instrumentationKey -o tsv 2>$null

    # Create logger
    Put-ApimResource -Path "loggers/appinsights" -Body @{
        properties = @{
            loggerType  = "applicationInsights"
            description = "App Insights logger"
            resourceId  = $appInsightsId
            credentials = @{ instrumentationKey = $instrumentationKey }
        }
    }

    # Create API diagnostics
    foreach ($apiId in @("function-api", "web-api", "legacy-api")) {
        Put-ApimResource -Path "apis/$apiId/diagnostics/applicationinsights" -Body @{
            properties = @{
                loggerId        = "${apimBase}/loggers/appinsights"
                alwaysLog       = "allErrors"
                verbosity       = "information"
                sampling        = @{ samplingType = "fixed"; percentage = 100 }
            }
        }
    }
}
catch {
    Write-Warning "APIM diagnostics setup failed. Configure manually in Portal: APIM > APIs > Settings > Diagnostics."
}

Write-Host "APIM configuration complete."
Write-Host "Gateway: https://$($env:APIM_NAME).azure-api.net"
