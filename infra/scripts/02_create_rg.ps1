[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. "$PSScriptRoot/_vars.ps1"

Write-Section "Step 2 - Create resource group"

try {
    $account = az account show -o json | ConvertFrom-Json
}
catch {
    throw "Azure CLI is not logged in or unavailable. Run: az login"
}

Write-Host "Subscription: $($account.name) ($($account.id))"
Write-Host "Target resource group: $ResourceGroupName"
Write-Host "Target location: $Location"

$exists = ((az group exists --name $ResourceGroupName -o tsv).Trim().ToLowerInvariant() -eq "true")
if ($exists) {
    $rg = az group show --name $ResourceGroupName -o json | ConvertFrom-Json
    Write-Host "Resource group already exists."
}
else {
    $rg = az group create --name $ResourceGroupName --location $Location -o json | ConvertFrom-Json
    Write-Host "Resource group created."
}

Write-Host "Resource group status:"
Write-Host "  Name: $($rg.name)"
Write-Host "  Location: $($rg.location)"
Write-Host "  Provisioning state: $($rg.properties.provisioningState)"
Write-Host "  ID: $($rg.id)"
