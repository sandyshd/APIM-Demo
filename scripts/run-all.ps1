param(
    [string]$EnvFile = "./scripts/env.local",
    [string]$GeneratedEnvFile = "./scripts/.generated.env",
    [switch]$SkipPrereqs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$steps = @(
    @{ Name = "00-prereqs-check"; Path = "./scripts/00-prereqs-check.ps1"; Args = @{ EnvFile = $EnvFile }; CanSkip = $true },
    @{ Name = "01-provision-azure-resources"; Path = "./scripts/01-provision-azure-resources.ps1"; Args = @{ EnvFile = $EnvFile; GeneratedEnvFile = $GeneratedEnvFile } },
    @{ Name = "02-deploy-function"; Path = "./scripts/02-deploy-function.ps1"; Args = @{ GeneratedEnvFile = $GeneratedEnvFile } },
    @{ Name = "03-deploy-webapi"; Path = "./scripts/03-deploy-webapi.ps1"; Args = @{ GeneratedEnvFile = $GeneratedEnvFile } },
    @{ Name = "04-provision-onprem-vm"; Path = "./scripts/04-provision-onprem-vm.ps1"; Args = @{ GeneratedEnvFile = $GeneratedEnvFile } },
    @{ Name = "05-deploy-onprem-api"; Path = "./scripts/05-deploy-onprem-api.ps1"; Args = @{ GeneratedEnvFile = $GeneratedEnvFile } },
    @{ Name = "06-configure-apim"; Path = "./scripts/06-configure-apim.ps1"; Args = @{ GeneratedEnvFile = $GeneratedEnvFile } },
    @{ Name = "07-test-calls"; Path = "./scripts/07-test-calls.ps1"; Args = @{ GeneratedEnvFile = $GeneratedEnvFile } }
)

function Invoke-Step {
    param(
        [int]$Index,
        [int]$Total,
        [hashtable]$Step
    )

    if (-not (Test-Path $Step.Path)) {
        throw "Step script not found: $($Step.Path)"
    }

    $start = Get-Date
    Write-Host "[$Index/$Total] START $($Step.Name)" -ForegroundColor Cyan

    $global:LASTEXITCODE = 0
    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $stepArgs = $Step.Args
        & $Step.Path @stepArgs
        $ErrorActionPreference = $prevPref
    }
    catch {
        throw "Step '$($Step.Name)' failed: $_"
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Step '$($Step.Name)' failed with exit code $LASTEXITCODE."
    }

    $elapsed = (Get-Date) - $start
    Write-Host "[$Index/$Total] DONE  $($Step.Name) in $([int]$elapsed.TotalSeconds)s" -ForegroundColor Green
    Write-Host ""
}

$executionPlan = if ($SkipPrereqs) {
    $steps | Where-Object { -not $_.CanSkip }
} else {
    $steps
}

Write-Host "Running APIM demo setup pipeline..." -ForegroundColor Yellow
Write-Host "Env file: $EnvFile"
Write-Host "Generated env: $GeneratedEnvFile"
if ($SkipPrereqs) {
    Write-Host "Prerequisites step skipped by -SkipPrereqs" -ForegroundColor Yellow
}
Write-Host ""

$total = $executionPlan.Count

for ($i = 0; $i -lt $total; $i++) {
    Invoke-Step -Index ($i + 1) -Total $total -Step $executionPlan[$i]
}

Write-Host "Pipeline completed successfully." -ForegroundColor Green
