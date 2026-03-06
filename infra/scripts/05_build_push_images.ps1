[CmdletBinding()]
param(
    [string]$Tag = ("v0.1.0-{0:yyyyMMddHHmm}" -f (Get-Date)),
    [ValidateSet("auto", "docker", "acr")]
    [string]$BuildMode = "auto"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. "$PSScriptRoot/_vars.ps1"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$outDir = Join-Path $repoRoot "infra\out"
$infraOutputsFile = Join-Path $outDir "infra.outputs.json"
$tagFile = Join-Path $outDir "image.tag.txt"

if (-not (Test-Path -Path $outDir -PathType Container)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

function Get-InfraOutputValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Outputs,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Outputs.PSObject.Properties.Name -contains $Name) {
        return [string]$Outputs.$Name.value
    }

    return ""
}

function Resolve-AcrInfo {
    $acrName = ""
    $acrLoginServer = ""

    if (Test-Path -Path $infraOutputsFile -PathType Leaf) {
        try {
            $outputs = Get-Content -Path $infraOutputsFile -Raw | ConvertFrom-Json
            $acrName = Get-InfraOutputValue -Outputs $outputs -Name "acrName"
            $acrLoginServer = Get-InfraOutputValue -Outputs $outputs -Name "acrLoginServer"
        }
        catch {
            Write-Host "Could not parse $infraOutputsFile. Falling back to Azure query."
        }
    }

    if ([string]::IsNullOrWhiteSpace($acrName) -or [string]::IsNullOrWhiteSpace($acrLoginServer)) {
        $acr = az acr list --resource-group $ResourceGroupName --query "[0].{name:name,loginServer:loginServer}" -o json | ConvertFrom-Json
        if (-not $acr -or [string]::IsNullOrWhiteSpace([string]$acr.name) -or [string]::IsNullOrWhiteSpace([string]$acr.loginServer)) {
            throw "Unable to resolve ACR details. Run 03_deploy_infra_baseline.ps1 first."
        }

        $acrName = [string]$acr.name
        $acrLoginServer = [string]$acr.loginServer
    }

    return [pscustomobject]@{
        Name = $acrName
        LoginServer = $acrLoginServer
    }
}

function Test-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Test-DockerDaemon {
    if (-not (Test-CommandExists -CommandName "docker")) {
        return $false
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        docker info --format "{{.ServerVersion}}" 1>$null 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [ScriptBlock]$Command
    )

    Write-Host $Description
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

Write-Section "Step 5 - Build and push images"

$acr = Resolve-AcrInfo
Write-Host "Using ACR: $($acr.Name) ($($acr.LoginServer))"
Write-Host "Image tag: $Tag"
$backendContext = Join-Path $repoRoot "backend"
$backendDockerfile = Join-Path $backendContext "Dockerfile"
$frontendContext = Join-Path $repoRoot "frontend"
$frontendDockerfile = Join-Path $frontendContext "Dockerfile"

if (-not (Test-Path -Path $backendDockerfile -PathType Leaf)) {
    throw "Backend Dockerfile not found: $backendDockerfile"
}
if (-not (Test-Path -Path $frontendDockerfile -PathType Leaf)) {
    throw "Frontend Dockerfile not found: $frontendDockerfile"
}

$backendImage = "$($acr.LoginServer)/ekip-backend:$Tag"
$workerImage = "$($acr.LoginServer)/ekip-worker:$Tag"
$frontendImage = "$($acr.LoginServer)/ekip-frontend:$Tag"

$effectiveBuildMode = switch ($BuildMode) {
    "docker" {
        if (-not (Test-DockerDaemon)) {
            throw "BuildMode 'docker' was requested, but Docker daemon is not available."
        }
        "docker"
    }
    "acr" { "acr" }
    default {
        if (Test-DockerDaemon) { "docker" } else { "acr" }
    }
}

Write-Host "Build mode: $effectiveBuildMode"

if ($effectiveBuildMode -eq "docker") {
    Invoke-CheckedCommand -Description "Logging into ACR with Docker..." -Command {
        az acr login --name $acr.Name --only-show-errors | Out-Null
    }

    Invoke-CheckedCommand -Description "Building backend image..." -Command {
        docker build --file $backendDockerfile --tag $backendImage $backendContext
    }

    Invoke-CheckedCommand -Description "Tagging worker image from backend build..." -Command {
        docker tag $backendImage $workerImage
    }

    Invoke-CheckedCommand -Description "Building frontend image..." -Command {
        docker build --file $frontendDockerfile --tag $frontendImage $frontendContext
    }

    Invoke-CheckedCommand -Description "Pushing backend image..." -Command {
        docker push $backendImage
    }

    Invoke-CheckedCommand -Description "Pushing worker image..." -Command {
        docker push $workerImage
    }

    Invoke-CheckedCommand -Description "Pushing frontend image..." -Command {
        docker push $frontendImage
    }
}
else {
    Write-Host "Docker daemon unavailable. Falling back to ACR cloud build."

    Invoke-CheckedCommand -Description "Building backend+worker images in ACR..." -Command {
        az acr build --registry $acr.Name --image "ekip-backend:$Tag" --image "ekip-worker:$Tag" --file $backendDockerfile $backendContext --only-show-errors
    }

    Invoke-CheckedCommand -Description "Building frontend image in ACR..." -Command {
        az acr build --registry $acr.Name --image "ekip-frontend:$Tag" --file $frontendDockerfile $frontendContext --only-show-errors
    }
}

Set-Content -Path $tagFile -Value $Tag -Encoding utf8
Write-Host "Image tag written to: $tagFile"
