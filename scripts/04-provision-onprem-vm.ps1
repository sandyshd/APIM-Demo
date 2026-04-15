param(
    [string]$GeneratedEnvFile = "./scripts/.generated.env"
)

. "$PSScriptRoot/common.ps1"
Load-EnvFile -Path $GeneratedEnvFile

# Expand $HOME in SSH paths
$env:SSH_PUBLIC_KEY_PATH = $env:SSH_PUBLIC_KEY_PATH -replace '\$HOME', $HOME
$env:SSH_PRIVATE_KEY_PATH = $env:SSH_PRIVATE_KEY_PATH -replace '\$HOME', $HOME

if (-not (Test-Path $env:SSH_PUBLIC_KEY_PATH)) {
    throw "SSH public key not found: $($env:SSH_PUBLIC_KEY_PATH)"
}

Write-Host "Creating NSG and allowing SSH (22) + demo API (5000)..."
az network nsg create `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:ONPREM_NSG `
  --location $env:LOCATION `
  --output none

az network nsg rule create `
  --resource-group $env:RESOURCE_GROUP `
  --nsg-name $env:ONPREM_NSG `
  --name AllowSSH `
  --priority 1000 `
  --destination-port-ranges 22 `
  --access Allow `
  --protocol Tcp `
  --output none

az network nsg rule create `
  --resource-group $env:RESOURCE_GROUP `
  --nsg-name $env:ONPREM_NSG `
  --name AllowLegacyApi `
  --priority 1010 `
  --destination-port-ranges 5000 `
  --access Allow `
  --protocol Tcp `
  --output none

Write-Host "Creating on-prem simulation network..."
az network vnet create `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:ONPREM_VNET `
  --location $env:LOCATION `
  --address-prefix 10.60.0.0/16 `
  --subnet-name $env:ONPREM_SUBNET `
  --subnet-prefixes 10.60.1.0/24 `
  --network-security-group $env:ONPREM_NSG `
  --output none

az network public-ip create `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:ONPREM_PIP `
  --sku Standard `
  --allocation-method Static `
  --output none

az network nic create `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:ONPREM_NIC `
  --vnet-name $env:ONPREM_VNET `
  --subnet $env:ONPREM_SUBNET `
  --network-security-group $env:ONPREM_NSG `
  --public-ip-address $env:ONPREM_PIP `
  --output none

Write-Host "Creating Ubuntu VM for on-prem simulation..."
az vm create `
  --resource-group $env:RESOURCE_GROUP `
  --name $env:ONPREM_VM `
  --nics $env:ONPREM_NIC `
  --image Ubuntu2204 `
  --size Standard_B1s `
  --admin-username $env:ONPREM_ADMIN_USER `
  --ssh-key-values $env:SSH_PUBLIC_KEY_PATH `
  --output none

$vmPublicIp = az network public-ip show --resource-group $env:RESOURCE_GROUP --name $env:ONPREM_PIP --query ipAddress -o tsv

$updated = @{}
Get-Content $GeneratedEnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
        $parts = $line -split "=", 2
        $updated[$parts[0]] = $parts[1]
    }
}
$updated["ONPREM_VM_PUBLIC_IP"] = $vmPublicIp
Save-GeneratedEnv -Path $GeneratedEnvFile -Values $updated

Write-Host "On-prem VM ready at $vmPublicIp"
