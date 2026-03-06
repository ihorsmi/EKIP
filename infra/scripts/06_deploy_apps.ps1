[CmdletBinding()]
param(
    [string]$Tag = "",
    [string]$DeploymentName = "ekip-apps"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. "$PSScriptRoot/_vars.ps1"

function Get-NormalizedLocation {
    param(
        [string]$Location
    )

    if ([string]::IsNullOrWhiteSpace($Location)) {
        return ""
    }

    return (($Location -replace "\s+", "") -replace "-", "").ToLowerInvariant()
}

function Get-ExistingResourceLocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,
        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    try {
        $locationRaw = az resource show --resource-group $ResourceGroupName --resource-type $ResourceType --name $ResourceName --query location -o tsv 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "$locationRaw".Trim()
        }
    }
    catch {
    }

    return ""
}

function Resolve-EffectiveLocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedLocation,
        [string]$ExistingLocation = "",
        [Parameter(Mandatory = $true)]
        [string]$ResourceLabel
    )

    if ([string]::IsNullOrWhiteSpace($ExistingLocation)) {
        return $RequestedLocation
    }

    if ((Get-NormalizedLocation -Location $ExistingLocation) -ne (Get-NormalizedLocation -Location $RequestedLocation)) {
        Write-Warning "$ResourceLabel exists in '$ExistingLocation'. Requested location '$RequestedLocation' is being overridden for this deployment."
        return $ExistingLocation
    }

    return $RequestedLocation
}

function Resolve-EffectiveDeploymentName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedName
    )

    $existingState = ""
    try {
        $stateRaw = az deployment group show --resource-group $ResourceGroupName --name $RequestedName --query properties.provisioningState -o tsv 2>$null
        if ($LASTEXITCODE -eq 0) {
            $existingState = "$stateRaw".Trim()
        }
    }
    catch {
    }

    if ($existingState -in @("Accepted", "Running")) {
        $generatedName = "$RequestedName-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Warning "Deployment '$RequestedName' is currently '$existingState'. Using '$generatedName' for this run."
        return $generatedName
    }

    return $RequestedName
}

function Get-DeploymentProvisioningState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploymentNameToCheck
    )

    try {
        $stateRaw = az deployment group show --resource-group $ResourceGroupName --name $DeploymentNameToCheck --query properties.provisioningState -o tsv 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "$stateRaw".Trim()
        }
    }
    catch {
    }

    return ""
}

function Stop-ActiveDeploymentIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploymentNameToStop
    )

    if ([string]::IsNullOrWhiteSpace($DeploymentNameToStop)) {
        return
    }

    $state = Get-DeploymentProvisioningState -DeploymentNameToCheck $DeploymentNameToStop
    if ($state -notin @("Accepted", "Running")) {
        return
    }

    Write-Warning "Cancelling active deployment '$DeploymentNameToStop' (state: $state)..."
    az deployment group cancel --resource-group $ResourceGroupName --name $DeploymentNameToStop 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Cancelled deployment: $DeploymentNameToStop"
    }
    else {
        Write-Warning "Could not cancel deployment '$DeploymentNameToStop'. It may have already completed."
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$templateFile = Join-Path $repoRoot "infra\bicep\main.bicep"
$paramsFile = Join-Path $repoRoot "infra\bicep\params\demo.apps.parameters.json"
$outDir = Join-Path $repoRoot "infra\out"
$kvSecretsFile = Join-Path $outDir "kv.secrets.json"
$tagFile = Join-Path $outDir "image.tag.txt"
$appsOutputsFile = Join-Path $outDir "apps.outputs.json"

if (-not (Test-Path -Path $templateFile -PathType Leaf)) {
    throw "Template file not found: $templateFile"
}
if (-not (Test-Path -Path $paramsFile -PathType Leaf)) {
    throw "Parameters file not found: $paramsFile"
}
if (-not (Test-Path -Path $kvSecretsFile -PathType Leaf)) {
    throw "Secret ID file not found: $kvSecretsFile. Run 04_set_keyvault_secrets.ps1 first."
}
if (-not (Test-Path -Path $outDir -PathType Container)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($Tag)) {
    if (-not (Test-Path -Path $tagFile -PathType Leaf)) {
        throw "No -Tag provided and $tagFile does not exist. Run 05_build_push_images.ps1 first or pass -Tag."
    }
    $Tag = (Get-Content -Path $tagFile -Raw).Trim()
}

if ([string]::IsNullOrWhiteSpace($Tag)) {
    throw "Image tag is empty."
}

$secrets = Get-Content -Path $kvSecretsFile -Raw | ConvertFrom-Json
$requiredSecretIdFields = @(
    "openaiApiKeySecretId",
    "searchAdminKeySecretId",
    "serviceBusConnStringSecretId",
    "storageConnStringSecretId",
    "cosmosKeySecretId"
)

foreach ($field in $requiredSecretIdFields) {
    if (-not ($secrets.PSObject.Properties.Name -contains $field) -or [string]::IsNullOrWhiteSpace([string]$secrets.$field)) {
        throw "Missing required field '$field' in $kvSecretsFile."
    }
}

Write-Section "Step 6 - Deploy apps (deployApps=true)"
Write-Host "Deployment name: $DeploymentName"
Write-Host "Resource group: $ResourceGroupName"
Write-Host "Image tag: $Tag"
Write-Host "Parameters: $paramsFile"
Write-Host "Cosmos location override: $CosmosLocation"
Write-Host "Apps location override: $AppsLocation"
Write-Host "Deploy OpenAI models: $DeployModels"

$rgExists = ((az group exists --name $ResourceGroupName -o tsv).Trim().ToLowerInvariant() -eq "true")
if (-not $rgExists) {
    throw "Resource group '$ResourceGroupName' does not exist. Run 02_create_rg.ps1 first."
}

$existingEnvLocation = Get-ExistingResourceLocation -ResourceType "Microsoft.App/managedEnvironments" -ResourceName $ContainerAppsEnvName
$effectiveAppsLocation = Resolve-EffectiveLocation -RequestedLocation $AppsLocation -ExistingLocation $existingEnvLocation -ResourceLabel "Managed environment '$ContainerAppsEnvName'"

$existingCosmosLocation = Get-ExistingResourceLocation -ResourceType "Microsoft.DocumentDB/databaseAccounts" -ResourceName $CosmosName
$effectiveCosmosLocation = Resolve-EffectiveLocation -RequestedLocation $CosmosLocation -ExistingLocation $existingCosmosLocation -ResourceLabel "Cosmos account '$CosmosName'"

$effectiveDeploymentName = Resolve-EffectiveDeploymentName -RequestedName $DeploymentName
Write-Host "Effective deployment name: $effectiveDeploymentName"
Write-Host "Effective cosmos location: $effectiveCosmosLocation"
Write-Host "Effective apps location: $effectiveAppsLocation"

# Previous failed runs can leave nested module deployments active with fixed names.
# Cancel them proactively to avoid DeploymentActive conflicts.
$nestedDeploymentNames = @(
    "observability-$Prefix-$Suffix",
    "base-$Prefix-$Suffix",
    "messaging-$Prefix-$Suffix",
    "search-$Prefix-$Suffix",
    "cosmos-$Prefix-$Suffix",
    "openai-$Prefix-$Suffix",
    "foundry-$Prefix-$Suffix",
    "apps-$Prefix-$Suffix"
)
$nestedDeploymentNames += $DeploymentName
$nestedDeploymentNames += $effectiveDeploymentName

$nestedDeploymentNames |
    Sort-Object -Unique |
    ForEach-Object { Stop-ActiveDeploymentIfNeeded -DeploymentNameToStop $_ }

$createArgs = @(
    "deployment", "group", "create",
    "--resource-group", $ResourceGroupName,
    "--name", $effectiveDeploymentName,
    "--template-file", $templateFile,
    "--parameters", "@$paramsFile",
    "deployApps=true",
    "imageTag=$Tag",
    "cosmosLocation=$effectiveCosmosLocation",
    "appsLocation=$effectiveAppsLocation",
    "deployModels=$DeployModels",
    "openAiApiKeySecretId=$($secrets.openaiApiKeySecretId)",
    "searchAdminKeySecretId=$($secrets.searchAdminKeySecretId)",
    "serviceBusConnectionStringSecretId=$($secrets.serviceBusConnStringSecretId)",
    "storageConnectionStringSecretId=$($secrets.storageConnStringSecretId)",
    "cosmosKeySecretId=$($secrets.cosmosKeySecretId)",
    "--query", "properties.outputs",
    "-o", "json"
)

$outputsJson = az @createArgs
if ($LASTEXITCODE -ne 0) {
    throw "Deployment '$effectiveDeploymentName' failed. Check deployment operations in Azure for details."
}
$outputs = $outputsJson | ConvertFrom-Json
$outputs | ConvertTo-Json -Depth 100 | Set-Content -Path $appsOutputsFile -Encoding utf8

$backendUrl = ""
$frontendUrl = ""
if ($outputs.PSObject.Properties.Name -contains "backendUrl") {
    $backendUrl = [string]$outputs.backendUrl.value
}
if ($outputs.PSObject.Properties.Name -contains "frontendUrl") {
    $frontendUrl = [string]$outputs.frontendUrl.value
}

Write-Host "App deployment outputs written to: $appsOutputsFile"
if (-not [string]::IsNullOrWhiteSpace($backendUrl)) {
    Write-Host "Backend URL: $backendUrl"
}
if (-not [string]::IsNullOrWhiteSpace($frontendUrl)) {
    Write-Host "Frontend URL: $frontendUrl"
}
