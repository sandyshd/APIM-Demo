param(
    [string]$GeneratedEnvFile = "./scripts/.generated.env"
)

. "$PSScriptRoot/common.ps1"
Load-EnvFile -Path $GeneratedEnvFile

# Expand $HOME in SSH paths
$env:SSH_PUBLIC_KEY_PATH = $env:SSH_PUBLIC_KEY_PATH -replace '\$HOME', $HOME
$env:SSH_PRIVATE_KEY_PATH = $env:SSH_PRIVATE_KEY_PATH -replace '\$HOME', $HOME

if (-not $env:ONPREM_VM_PUBLIC_IP) {
    throw "ONPREM_VM_PUBLIC_IP missing. Run script 04 first."
}

if (-not (Test-Path $env:SSH_PRIVATE_KEY_PATH)) {
    throw "SSH private key not found: $($env:SSH_PRIVATE_KEY_PATH)"
}

$publishDir = Join-Path $PSScriptRoot "../out/legacy"
if (Test-Path $publishDir) { Remove-Item -Recurse -Force $publishDir }
New-Item -ItemType Directory -Path $publishDir -Force | Out-Null

Write-Host "Publishing Legacy API..."
dotnet publish "$PSScriptRoot/../src/LegacyApiSim/LegacyApiSim.csproj" -c Release -o $publishDir

$target = "$($env:ONPREM_ADMIN_USER)@$($env:ONPREM_VM_PUBLIC_IP)"

Write-Host "Copying published files to VM..."
$scpDest = $target + ":/tmp/legacyapi/"
scp -i $env:SSH_PRIVATE_KEY_PATH -o StrictHostKeyChecking=accept-new -r "$publishDir/*" $scpDest

# Write remote setup script to a local temp file, SCP it, then execute remotely
$setupScript = Join-Path $PSScriptRoot "../out/setup-legacy.sh"
@"
#!/bin/bash
set -e
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
curl -sSL https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb
sudo dpkg -i /tmp/packages-microsoft-prod.deb
sudo apt-get update -y
sudo apt-get install -y aspnetcore-runtime-8.0

sudo mkdir -p /opt/legacyapi
sudo cp -r /tmp/legacyapi/* /opt/legacyapi/
sudo chown -R root:root /opt/legacyapi

sudo tee /etc/systemd/system/legacyapi.service > /dev/null <<'SVCEOF'
[Unit]
Description=Legacy API Simulator
After=network.target

[Service]
WorkingDirectory=/opt/legacyapi
ExecStart=/usr/bin/dotnet /opt/legacyapi/LegacyApiSim.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=legacyapi
User=root
Environment=ASPNETCORE_URLS=http://0.0.0.0:5000

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable legacyapi
sudo systemctl restart legacyapi
sudo systemctl status legacyapi --no-pager
"@ | Set-Content -Path $setupScript -NoNewline -Encoding utf8NoBOM
# Convert CRLF to LF for Linux
(Get-Content $setupScript -Raw) -replace "`r`n", "`n" | Set-Content -Path $setupScript -NoNewline -Encoding utf8NoBOM

Write-Host "Uploading setup script to VM..."
$scpSetup = $target + ":/tmp/setup-legacy.sh"
scp -i $env:SSH_PRIVATE_KEY_PATH -o StrictHostKeyChecking=accept-new $setupScript $scpSetup

Write-Host "Installing runtime and configuring systemd service on VM..."
ssh -i $env:SSH_PRIVATE_KEY_PATH -o StrictHostKeyChecking=accept-new $target "chmod +x /tmp/setup-legacy.sh && /tmp/setup-legacy.sh"

Write-Host "Legacy API deployed: http://$($env:ONPREM_VM_PUBLIC_IP):5000/legacy/status"
