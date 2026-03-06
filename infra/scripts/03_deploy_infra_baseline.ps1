[CmdletBinding()]
param(
    [string]$DeploymentName = "ekip-baseline"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. "$PSScriptRoot/_vars.ps1"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$templateFile = Join-Path $repoRoot "infra\bicep\main.bicep"
$paramsFile = Join-Path $repoRoot "infra\bicep\params\demo.parameters.json"
$outDir = Join-Path $repoRoot "infra\out"
$outputsFile = Join-Path $outDir "infra.outputs.json"

if (-not (Test-Path -Path $templateFile -PathType Leaf)) {
    throw "Template file not found: $templateFile"
}
if (-not (Test-Path -Path $paramsFile -PathType Leaf)) {
    throw "Parameters file not found: $paramsFile"
}
if (-not (Test-Path -Path $outDir -PathType Container)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

Write-Section "Step 3 - Deploy infra baseline (deployApps=false)"
Write-Host "Deployment name: $DeploymentName"
Write-Host "Resource group: $ResourceGroupName"
Write-Host "Template: $templateFile"
Write-Host "Parameters: $paramsFile"
Write-Host "Cosmos location override: $CosmosLocation"
Write-Host "Apps location override: $AppsLocation"
Write-Host "Deploy OpenAI models: $DeployModels"

$rgExists = ((az group exists --name $ResourceGroupName -o tsv).Trim().ToLowerInvariant() -eq "true")
if (-not $rgExists) {
    throw "Resource group '$ResourceGroupName' does not exist. Run 02_create_rg.ps1 first."
}

Write-Host "Running what-if..."
$whatIfArgs = @(
    "deployment", "group", "what-if",
    "--resource-group", $ResourceGroupName,
    "--name", $DeploymentName,
    "--template-file", $templateFile,
    "--parameters", "@$paramsFile",
    "deployApps=false",
    "cosmosLocation=$CosmosLocation",
    "appsLocation=$AppsLocation",
    "deployModels=$DeployModels",
    "--result-format", "FullResourcePayloads"
)
az @whatIfArgs
if ($LASTEXITCODE -ne 0) {
    throw "What-if failed for deployment '$DeploymentName'."
}

Write-Host "Applying deployment..."
$createArgs = @(
    "deployment", "group", "create",
    "--resource-group", $ResourceGroupName,
    "--name", $DeploymentName,
    "--template-file", $templateFile,
    "--parameters", "@$paramsFile",
    "deployApps=false",
    "cosmosLocation=$CosmosLocation",
    "appsLocation=$AppsLocation",
    "deployModels=$DeployModels",
    "--query", "properties.outputs",
    "-o", "json"
)
$outputsJson = az @createArgs
if ($LASTEXITCODE -ne 0) {
    throw "Deployment '$DeploymentName' failed. Check deployment operations in Azure for details."
}
$outputs = $outputsJson | ConvertFrom-Json
$outputs | ConvertTo-Json -Depth 100 | Set-Content -Path $outputsFile -Encoding utf8

Write-Host "Deployment outputs written to: $outputsFile"
