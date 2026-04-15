param(
    [string]$GeneratedEnvFile = "./scripts/.generated.env"
)

. "$PSScriptRoot/common.ps1"
Load-EnvFile -Path $GeneratedEnvFile

$gateway = "https://$($env:APIM_NAME).azure-api.net"

function Get-AccessToken {
    param(
        [string]$ClientId,
        [string]$ClientSecret
    )

    $tokenEndpoint = "https://login.microsoftonline.com/$($env:TENANT_ID)/oauth2/v2.0/token"
    $body = @{
        client_id = $ClientId
        client_secret = $ClientSecret
        scope = "$($env:API_AUDIENCE)/.default"
        grant_type = "client_credentials"
    }

    $result = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -ContentType "application/x-www-form-urlencoded" -Body $body
    return $result.access_token
}

function Invoke-DemoCall {
    param(
        [string]$Name,
        [string]$Uri,
        [hashtable]$Headers
    )

    $response = Invoke-WebRequest -Method Get -Uri $Uri -Headers $Headers -SkipHttpErrorCheck
    Write-Host "[$Name] Status=$($response.StatusCode) Uri=$Uri"
    if ($response.Content) {
        Write-Host $response.Content
    }
    Write-Host ""
}

$subscriptionKey = az apim subscription show --resource-group $env:RESOURCE_GROUP --service-name $env:APIM_NAME --sid $env:APIM_SUBSCRIPTION_ID --query primaryKey -o tsv

$adminToken = Get-AccessToken -ClientId $env:ADMIN_CLIENT_ID -ClientSecret $env:ADMIN_CLIENT_SECRET
$userToken = Get-AccessToken -ClientId $env:USER_CLIENT_ID -ClientSecret $env:USER_CLIENT_SECRET

Invoke-DemoCall -Name "No key, no token (expected 401/403)" -Uri "$gateway/function/hello" -Headers @{}
Invoke-DemoCall -Name "Key but no token (expected 401)" -Uri "$gateway/function/hello" -Headers @{ "Ocp-Apim-Subscription-Key" = $subscriptionKey }
Invoke-DemoCall -Name "Key + user token on admin route (expected 403)" -Uri "$gateway/v1/web/admin/health" -Headers @{ "Ocp-Apim-Subscription-Key" = $subscriptionKey; "Authorization" = "Bearer $userToken" }
Invoke-DemoCall -Name "Key + admin token (expected 200)" -Uri "$gateway/v1/web/admin/health" -Headers @{ "Ocp-Apim-Subscription-Key" = $subscriptionKey; "Authorization" = "Bearer $adminToken" }
Invoke-DemoCall -Name "Function orders success (expected 200)" -Uri "$gateway/function/orders" -Headers @{ "Ocp-Apim-Subscription-Key" = $subscriptionKey; "Authorization" = "Bearer $adminToken" }
Invoke-DemoCall -Name "Legacy customers success (expected 200)" -Uri "$gateway/legacy/customers" -Headers @{ "Ocp-Apim-Subscription-Key" = $subscriptionKey; "Authorization" = "Bearer $adminToken" }
Invoke-DemoCall -Name "Web version v1 products" -Uri "$gateway/v1/web/products" -Headers @{ "Ocp-Apim-Subscription-Key" = $subscriptionKey; "Authorization" = "Bearer $adminToken" }
Invoke-DemoCall -Name "Web version v2 products (breaking schema)" -Uri "$gateway/v2/web/products" -Headers @{ "Ocp-Apim-Subscription-Key" = $subscriptionKey; "Authorization" = "Bearer $adminToken" }
