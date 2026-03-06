[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. "$PSScriptRoot/_vars.ps1"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$appsOutputsFile = Join-Path $repoRoot "infra\out\apps.outputs.json"

if (-not (Test-Path -Path $appsOutputsFile -PathType Leaf)) {
    throw "Missing $appsOutputsFile. Run 06_deploy_apps.ps1 first."
}

Write-Section "Step 7 - Smoke test"

$outputs = Get-Content -Path $appsOutputsFile -Raw | ConvertFrom-Json

$backendUrl = ""
$frontendUrl = ""
if ($outputs.PSObject.Properties.Name -contains "backendUrl") {
    $backendUrl = [string]$outputs.backendUrl.value
}
if ($outputs.PSObject.Properties.Name -contains "frontendUrl") {
    $frontendUrl = [string]$outputs.frontendUrl.value
}

if ([string]::IsNullOrWhiteSpace($backendUrl)) {
    throw "backendUrl output is missing in $appsOutputsFile."
}
if ([string]::IsNullOrWhiteSpace($frontendUrl)) {
    throw "frontendUrl output is missing in $appsOutputsFile."
}

$healthUrl = "$($backendUrl.TrimEnd('/'))/health"
Write-Host "Checking backend health endpoint: $healthUrl"

$statusCode = 0
$request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($healthUrl)
$request.Method = "GET"
$request.Timeout = 60000

try {
    $response = [System.Net.HttpWebResponse]$request.GetResponse()
    try {
        $statusCode = [int]$response.StatusCode
    }
    finally {
        $response.Close()
    }
}
catch [System.Net.WebException] {
    $webException = [System.Net.WebException]$_.Exception
    if ($webException.Response) {
        $errorResponse = [System.Net.HttpWebResponse]$webException.Response
        try {
            $statusCode = [int]$errorResponse.StatusCode
        }
        finally {
            $errorResponse.Close()
        }
    }
    else {
        throw "Backend health check failed: $($webException.Message)"
    }
}

if ($statusCode -ne 200) {
    throw "Backend health check returned status code $statusCode (expected 200)."
}

Write-Host "Smoke test passed."
Write-Host "Backend URL: $backendUrl"
Write-Host "Frontend URL: $frontendUrl"
Write-Host "Next steps:"
Write-Host "  1) Open the frontend URL and run a basic chat flow."
Write-Host "  2) Validate ingestion and worker processing from app logs."
Write-Host "  3) Store these URLs in your release notes."
