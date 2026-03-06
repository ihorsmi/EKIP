[CmdletBinding()]
param(
    [string]$BackendUrl = "",
    [string]$FilePath = "README.md",
    [string]$Question = "What is EKIP according to the uploaded README?",
    [int]$PollSeconds = 8,
    [int]$MaxPolls = 20
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$appsOutputsFile = Join-Path $repoRoot "infra\out\apps.outputs.json"

function Resolve-BackendUrl {
    param([string]$ExplicitUrl)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitUrl)) {
        return $ExplicitUrl.TrimEnd("/")
    }

    if (-not (Test-Path -Path $appsOutputsFile -PathType Leaf)) {
        throw "Backend URL not provided and apps outputs not found: $appsOutputsFile"
    }

    $outputs = Get-Content -Path $appsOutputsFile -Raw | ConvertFrom-Json
    $url = [string]$outputs.backendUrl.value
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "backendUrl is empty in $appsOutputsFile"
    }
    return $url.TrimEnd("/")
}

$backend = Resolve-BackendUrl -ExplicitUrl $BackendUrl
$resolvedFile = Resolve-Path -Path (Join-Path $repoRoot $FilePath)

Write-Host "Backend: $backend"
Write-Host "File: $resolvedFile"

Write-Host ""
Write-Host "1) Health check"
$health = Invoke-RestMethod -Method Get -Uri "$backend/health" -TimeoutSec 30
$health | ConvertTo-Json -Depth 6 | Write-Host

Write-Host ""
Write-Host "2) Upload"
$uploadRaw = curl.exe -sS -X POST "$backend/upload" -F "file=@$resolvedFile"
$upload = $uploadRaw | ConvertFrom-Json
$jobId = [string]$upload.job_id
if ([string]::IsNullOrWhiteSpace($jobId)) {
    throw "Upload did not return job_id. Raw response: $uploadRaw"
}
Write-Host "job_id: $jobId"

Write-Host ""
Write-Host "3) Poll ingestion job"
$finalJob = $null
for ($i = 1; $i -le $MaxPolls; $i++) {
    Start-Sleep -Seconds $PollSeconds
    $job = Invoke-RestMethod -Method Get -Uri "$backend/upload/$jobId" -TimeoutSec 30
    Write-Host ("poll #{0}: status={1}, chunks={2}" -f $i, $job.status, $job.chunks_indexed)
    if ($job.status -in @("completed", "failed")) {
        $finalJob = $job
        break
    }
}

if ($null -eq $finalJob) {
    throw "Ingestion did not reach completed/failed after $MaxPolls polls."
}

if ($finalJob.status -ne "completed") {
    throw "Ingestion failed. Error: $($finalJob.error)"
}

Write-Host ""
Write-Host "4) Query"
$queryBody = @{ question = $Question } | ConvertTo-Json
$queryResp = Invoke-RestMethod -Method Post -Uri "$backend/query" -ContentType "application/json" -Body $queryBody -TimeoutSec 90

Write-Host ("conversation_id: {0}" -f $queryResp.conversation_id)
Write-Host ("citations: {0}" -f (($queryResp.citations | Measure-Object).Count))
Write-Host ("answer: {0}" -f $queryResp.answer)
