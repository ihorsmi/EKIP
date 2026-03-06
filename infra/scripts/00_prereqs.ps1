[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/_vars.ps1"

$script:HasFailure = $false

function Write-Pass {
    param([string]$Message)
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:HasFailure = $true
}

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Fail "Missing required tool: $Name"
        return $false
    }

    Write-Pass "Found tool: $Name"
    return $true
}

function Get-CommandOutput {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    try {
        return (& $ScriptBlock 2>$null | Select-Object -First 1).ToString().Trim()
    }
    catch {
        Write-Fail $FailureMessage
        return ""
    }
}

Write-Section "Step 0 - Tool checks"

$hasAz = Assert-Command -Name "az"
$hasDocker = Assert-Command -Name "docker"

if ($hasAz) {
    $azCliVersion = Get-CommandOutput -ScriptBlock { az version --query '"azure-cli"' -o tsv } -FailureMessage "Unable to read Azure CLI version."
    if ($azCliVersion) {
        Write-Host "Azure CLI version: $azCliVersion"
    }

    $azBicepVersion = Get-CommandOutput -ScriptBlock { az bicep version } -FailureMessage "Azure CLI bicep component is missing. Run: az bicep install"
    if ($azBicepVersion) {
        Write-Host "Azure Bicep version: $azBicepVersion"
    }
}

if ($hasDocker) {
    $dockerVersion = Get-CommandOutput -ScriptBlock { docker version --format '{{.Client.Version}}' } -FailureMessage "Unable to read Docker version."
    if (-not $dockerVersion) {
        $dockerVersion = Get-CommandOutput -ScriptBlock { docker --version } -FailureMessage "Unable to read Docker version."
    }
    if ($dockerVersion) {
        Write-Host "Docker version: $dockerVersion"
    }
}

if ($script:HasFailure) {
    Write-Host ""
    Write-Host "One or more required local tools are missing." -ForegroundColor Red
    exit 1
}

Write-Section "Step 0 - Azure login and subscription"

try {
    $account = az account show -o json | ConvertFrom-Json
}
catch {
    Write-Fail "Azure CLI is not logged in. Run: az login"
    exit 1
}

if ($env:AZURE_SUBSCRIPTION_ID) {
    Write-Host "Setting subscription from AZURE_SUBSCRIPTION_ID: $($env:AZURE_SUBSCRIPTION_ID)"
    try {
        az account set --subscription $env:AZURE_SUBSCRIPTION_ID | Out-Null
        $account = az account show -o json | ConvertFrom-Json
        Write-Pass "Active subscription set to $($account.name) ($($account.id))."
    }
    catch {
        Write-Fail "Failed to set subscription $($env:AZURE_SUBSCRIPTION_ID)."
        exit 1
    }
}
else {
    Write-Host "AZURE_SUBSCRIPTION_ID is not set. Using current subscription."
    Write-Host "Subscription: $($account.name) ($($account.id))"
    Write-Host "Tenant: $($account.tenantId)"
}

Write-Section "Step 0 - Provider registration"

$providers = @(
    "Microsoft.App",
    "Microsoft.OperationalInsights",
    "Microsoft.KeyVault",
    "Microsoft.CognitiveServices",
    "Microsoft.Search",
    "Microsoft.DocumentDB",
    "Microsoft.Storage",
    "Microsoft.ServiceBus",
    "Microsoft.ContainerRegistry"
)

foreach ($provider in $providers) {
    try {
        $state = (az provider show --namespace $provider --query registrationState -o tsv 2>$null).Trim()
        if ($state -eq "Registered") {
            Write-Pass "$provider already registered."
            continue
        }

        Write-Host "Registering $provider (current state: $state)..."
        az provider register --namespace $provider --wait | Out-Null
        $stateAfter = (az provider show --namespace $provider --query registrationState -o tsv 2>$null).Trim()
        if ($stateAfter -eq "Registered") {
            Write-Pass "$provider registered."
        }
        else {
            Write-Fail "$provider registration state is '$stateAfter'."
        }
    }
    catch {
        Write-Fail "Provider registration failed for $provider. $($_.Exception.Message)"
    }
}

if ($script:HasFailure) {
    Write-Host ""
    Write-Host "Step 0 failed. Resolve the failures above and rerun." -ForegroundColor Red
    exit 1
}

Write-Section "Step 0 complete"
Write-Host "Prerequisites are ready for EKIP Azure deployment checks."
Write-Host "Next command:"
Write-Host "  pwsh -File .\\infra\\scripts\\01_stopship_check.ps1"
exit 0
