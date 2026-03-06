[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/_vars.ps1"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script:AnyFailure = $false

function Write-Pass {
    param([string]$Message)
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:AnyFailure = $true
}

function Write-Info {
    param([string]$Message)
    Write-Host "INFO: $Message" -ForegroundColor DarkGray
}

function Test-FileExists {
    param([string]$Path)
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        Write-Fail "Required file is missing: $Path"
        return $false
    }
    return $true
}

function Get-LineMatches {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $lines = Get-Content -Path $Path
    $lineMatches = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $Pattern) {
            $lineMatches += [pscustomobject]@{
                LineNumber = $i + 1
                Text       = $lines[$i]
            }
        }
    }
    return $lineMatches
}

function Format-Match {
    param(
        [string]$Path,
        [int]$LineNumber,
        [string]$Text
    )

    $relativePath = Resolve-Path -Relative -Path $Path
    return "${relativePath}:${LineNumber}: $($Text.Trim())"
}

function Get-ResourceBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$ResourceName
    )

    $startPattern = "resource\s+$ResourceName\s+'[^']+'\s*=\s*\{"
    $start = [regex]::Match($Content, $startPattern)
    if (-not $start.Success) {
        return $null
    }

    $openBraceIndex = $Content.IndexOf('{', $start.Index)
    if ($openBraceIndex -lt 0) {
        return $null
    }

    $depth = 0
    for ($i = $openBraceIndex; $i -lt $Content.Length; $i++) {
        $ch = $Content[$i]
        if ($ch -eq '{') {
            $depth++
        }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Content.Substring($start.Index, ($i - $start.Index + 1))
            }
        }
    }

    return $null
}

function Test-EnvValue {
    param(
        [string]$Block,
        [string]$Name,
        [string]$Value
    )

    $pattern = "name:\s*'$([regex]::Escape($Name))'\s*,\s*value:\s*'$([regex]::Escape($Value))'"
    return [regex]::IsMatch($Block, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Test-EnvSecretRef {
    param(
        [string]$Block,
        [string]$Name
    )

    $pattern = "name:\s*'$([regex]::Escape($Name))'\s*,\s*secretRef:\s*'[^']+'"
    return [regex]::IsMatch($Block, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Test-EnvPlainValue {
    param(
        [string]$Block,
        [string]$Name
    )

    $pattern = "name:\s*'$([regex]::Escape($Name))'\s*,\s*value:"
    return [regex]::IsMatch($Block, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

Write-Section "Step 1 - Stop-ship checks"

$cosmosBicepPath = Join-Path $repoRoot "infra\bicep\modules\cosmos.bicep"
$mainBicepPath = Join-Path $repoRoot "infra\bicep\main.bicep"
$containerAppsBicepPath = Join-Path $repoRoot "infra\bicep\modules\container-apps.bicep"
$backendCosmosStorePath = Join-Path $repoRoot "backend\core\cosmos_store.py"
$paramsPath = Join-Path $repoRoot "infra\bicep\params\demo.parameters.json"
$stepsDocPath = Join-Path $repoRoot "infra\DEPLOYMENT_STEPS_0_1.md"

$requiredFiles = @(
    $cosmosBicepPath,
    $mainBicepPath,
    $containerAppsBicepPath,
    $backendCosmosStorePath,
    $paramsPath,
    $stepsDocPath
)

$missingFile = $false
foreach ($path in $requiredFiles) {
    if (-not (Test-FileExists -Path $path)) {
        $missingFile = $true
    }
}

if ($missingFile) {
    Write-Fail "Stop-ship checks cannot continue because required files are missing."
    exit 1
}

$containerAppsText = Get-Content -Path $containerAppsBicepPath -Raw
$backendBlock = Get-ResourceBlock -Content $containerAppsText -ResourceName "backend"
$workerBlock = Get-ResourceBlock -Content $containerAppsText -ResourceName "worker"

if (-not $backendBlock -or -not $workerBlock) {
    Write-Fail "Unable to parse backend and worker resources in container-apps.bicep."
    exit 1
}

Write-Section "Check 1 - Cosmos partition key consistency"

$mainPartitionMatches = @(Get-LineMatches -Path $mainBicepPath -Pattern "partitionKeyPath\s*:\s*'[^']+'")
$modulePartitionDefaultMatches = @(Get-LineMatches -Path $cosmosBicepPath -Pattern "param\s+partitionKeyPath\s+string\s*=\s*'[^']+'")
$modulePartitionUsageMatches = @(Get-LineMatches -Path $cosmosBicepPath -Pattern "paths:\s*\[")
$backendPartitionMatches = @(Get-LineMatches -Path $backendCosmosStorePath -Pattern 'PartitionKey\(path\s*=\s*"[^"]+"')

$bicepPartitionPath = $null
if ($mainPartitionMatches.Count -gt 0) {
    $bicepPartitionPath = [regex]::Match($mainPartitionMatches[0].Text, "'([^']+)'").Groups[1].Value
}
elseif ($modulePartitionDefaultMatches.Count -gt 0) {
    $bicepPartitionPath = [regex]::Match($modulePartitionDefaultMatches[0].Text, "'([^']+)'").Groups[1].Value
}

$backendPartitionPaths = @()
foreach ($m in $backendPartitionMatches) {
    $backendPartitionPaths += [regex]::Match($m.Text, 'path\s*=\s*"([^"]+)"').Groups[1].Value
}
$backendPartitionPaths = @($backendPartitionPaths | Sort-Object -Unique)

$allowedPartitionPaths = @("/pk", "/conversationId")
$check1Passed = $true

if (-not $bicepPartitionPath) {
    $check1Passed = $false
    Write-Info "Could not resolve Cosmos partition key path from Bicep."
}

if ($backendPartitionPaths.Count -ne 1) {
    $check1Passed = $false
    Write-Info "backend/core/cosmos_store.py uses multiple or missing partition key paths."
}

if ($bicepPartitionPath -and $backendPartitionPaths.Count -eq 1) {
    $backendPartitionPath = $backendPartitionPaths[0]
    if ($bicepPartitionPath -ne $backendPartitionPath) {
        $check1Passed = $false
        Write-Info "Mismatch detected: Bicep uses '$bicepPartitionPath' but backend uses '$backendPartitionPath'."
    }
    if ($allowedPartitionPaths -notcontains $bicepPartitionPath) {
        $check1Passed = $false
        Write-Info "Bicep partition path '$bicepPartitionPath' is not one of: $($allowedPartitionPaths -join ', ')."
    }
}

foreach ($m in $mainPartitionMatches) {
    Write-Info (Format-Match -Path $mainBicepPath -LineNumber $m.LineNumber -Text $m.Text)
}
foreach ($m in $modulePartitionUsageMatches) {
    Write-Info (Format-Match -Path $cosmosBicepPath -LineNumber $m.LineNumber -Text $m.Text)
}
foreach ($m in $backendPartitionMatches) {
    Write-Info (Format-Match -Path $backendCosmosStorePath -LineNumber $m.LineNumber -Text $m.Text)
}

if ($check1Passed) {
    Write-Pass "Cosmos partition key path is consistent."
}
else {
    Write-Fail "Cosmos partition key mismatch or ambiguity found."
    Write-Host "Remediation: use one path everywhere (recommended: /pk) in both cosmos.bicep and backend/core/cosmos_store.py."
}

Write-Section "Check 2 - Container Apps provider env wiring"

$requiredProviderEnv = @(
    @{ Name = "EKIP_STATE_PROVIDER"; Value = "cosmos" },
    @{ Name = "EKIP_QUEUE_PROVIDER"; Value = "servicebus" },
    @{ Name = "EKIP_STORAGE_PROVIDER"; Value = "azureblob" },
    @{ Name = "EKIP_INDEX_PROVIDER"; Value = "azuresearch" }
)

$check2Passed = $true
foreach ($req in $requiredProviderEnv) {
    if (-not (Test-EnvValue -Block $backendBlock -Name $req.Name -Value $req.Value)) {
        Write-Info "Missing backend env: $($req.Name)=$($req.Value)"
        $check2Passed = $false
    }
    if (-not (Test-EnvValue -Block $workerBlock -Name $req.Name -Value $req.Value)) {
        Write-Info "Missing worker env: $($req.Name)=$($req.Value)"
        $check2Passed = $false
    }
}

if ($check2Passed) {
    Write-Pass "Backend and worker provider env vars are wired."
}
else {
    Write-Fail "Container Apps provider env wiring is incomplete."
    Write-Host "Remediation: set EKIP_STATE_PROVIDER, EKIP_QUEUE_PROVIDER, EKIP_STORAGE_PROVIDER, EKIP_INDEX_PROVIDER for both backend and worker."
}

Write-Section "Check 3 - Key Vault secret references"

$requiredSecretEnvVars = @(
    "AZURE_OPENAI_API_KEY",
    "AZURE_SEARCH_ADMIN_KEY",
    "AZURE_SERVICEBUS_CONNECTION_STRING",
    "AZURE_STORAGE_CONNECTION_STRING",
    "AZURE_COSMOS_KEY"
)

$requiredKeyVaultSecretNames = @(
    "openai-api-key",
    "search-admin-key",
    "servicebus-connection-string",
    "storage-connection-string",
    "cosmos-key"
)

$hasKeyVaultSecretObjects = $true
foreach ($secretName in $requiredKeyVaultSecretNames) {
    $pattern = "(?s)\{\s*name:\s*'$([regex]::Escape($secretName))'.*?keyVaultUrl:\s*[^`r`n]+.*?\}"
    if (-not [regex]::IsMatch($containerAppsText, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        Write-Info "Missing Key Vault secret object or keyVaultUrl for: $secretName"
        $hasKeyVaultSecretObjects = $false
    }
}

$allSecretRefsPresent = $true
$plainSecretUsageFound = $false
foreach ($varName in $requiredSecretEnvVars) {
    if (-not (Test-EnvSecretRef -Block $backendBlock -Name $varName)) {
        Write-Info "Backend missing secretRef env for $varName"
        $allSecretRefsPresent = $false
    }
    if (-not (Test-EnvSecretRef -Block $workerBlock -Name $varName)) {
        Write-Info "Worker missing secretRef env for $varName"
        $allSecretRefsPresent = $false
    }
    if ((Test-EnvPlainValue -Block $backendBlock -Name $varName) -or (Test-EnvPlainValue -Block $workerBlock -Name $varName)) {
        Write-Info "Sensitive env var uses plain value instead of secretRef: $varName"
        $plainSecretUsageFound = $true
    }
}

$check3Passed = $hasKeyVaultSecretObjects -and $allSecretRefsPresent -and (-not $plainSecretUsageFound)

if ($check3Passed) {
    Write-Pass "Key Vault secret references are wired for sensitive values."
}
else {
    Write-Fail "Key Vault secret reference wiring is incomplete or inconsistent."
    Write-Host "Remediation: define configuration.secrets with keyVaultUrl and map sensitive env vars through secretRef."
}

Write-Section "Check 4 - Data-plane RBAC and credential consistency"

$hasStorageBlobRole = ($containerAppsText -match "ba92f5b4-2d11-453d-a403-e96b0029c9fe") -and ($containerAppsText -match "resource\s+backendStorageBlobContributor") -and ($containerAppsText -match "resource\s+workerStorageBlobContributor")
$hasServiceBusSenderRole = ($containerAppsText -match "69a216fc-b8fb-44d8-bc22-1f3c2cd27a39") -and ($containerAppsText -match "resource\s+backendServiceBusSender") -and ($containerAppsText -match "resource\s+workerServiceBusSender")
$hasServiceBusReceiverRole = ($containerAppsText -match "4f6d3b9b-027b-4f9f-bb67-1ff8ff7e6a8e") -and ($containerAppsText -match "resource\s+backendServiceBusReceiver") -and ($containerAppsText -match "resource\s+workerServiceBusReceiver")
$hasKeyVaultSecretsUserRole = ($containerAppsText -match "4633458b-17de-408a-b874-0445c86b69e6") -and ($containerAppsText -match "resource\s+backendKeyVaultSecretsUser") -and ($containerAppsText -match "resource\s+workerKeyVaultSecretsUser")

$hasSearchRbacRoles = ($containerAppsText -match "8ebe5a00-799e-43f5-93ac-243d3dce84a7") -or ($containerAppsText -match "1407120a-92aa-4202-b7e9-c0e197c71c8f")
$hasSearchAdminKeyUsage = (Test-EnvSecretRef -Block $backendBlock -Name "AZURE_SEARCH_ADMIN_KEY") -and (Test-EnvSecretRef -Block $workerBlock -Name "AZURE_SEARCH_ADMIN_KEY")

$hasCosmosDataPlaneRbac = $containerAppsText -match "sqlRoleAssignments"
$hasCosmosKeyUsage = (Test-EnvSecretRef -Block $backendBlock -Name "AZURE_COSMOS_KEY") -and (Test-EnvSecretRef -Block $workerBlock -Name "AZURE_COSMOS_KEY")

$check4Passed = $true
if (-not $hasStorageBlobRole) {
    Write-Info "Missing Storage Blob Data Contributor role assignment."
    $check4Passed = $false
}
if (-not $hasServiceBusSenderRole) {
    Write-Info "Missing Service Bus Data Sender role assignment."
    $check4Passed = $false
}
if (-not $hasServiceBusReceiverRole) {
    Write-Info "Missing Service Bus Data Receiver role assignment."
    $check4Passed = $false
}
if (-not $hasKeyVaultSecretsUserRole) {
    Write-Info "Missing Key Vault Secrets User role assignment."
    $check4Passed = $false
}
if (-not ($hasSearchRbacRoles -or $hasSearchAdminKeyUsage)) {
    Write-Info "Search access model missing. Add Search RBAC role assignments or AZURE_SEARCH_ADMIN_KEY secret usage."
    $check4Passed = $false
}
if (-not ($hasCosmosDataPlaneRbac -or $hasCosmosKeyUsage)) {
    Write-Info "Cosmos access model missing. Add Cosmos data-plane RBAC assignment or AZURE_COSMOS_KEY secret usage."
    $check4Passed = $false
}

if ($check4Passed) {
    Write-Pass "Data-plane RBAC and key-based access paths are defined consistently."
}
else {
    Write-Fail "Data-plane RBAC/access wiring is incomplete."
    Write-Host "Remediation: keep ACR pull plus Storage/Service Bus/Key Vault roles, and choose either RBAC or key usage for Search and Cosmos."
}

Write-Section "Check 5 - Deterministic naming convention"

$mainText = Get-Content -Path $mainBicepPath -Raw
$docText = Get-Content -Path $stepsDocPath -Raw

$requiredMainPatterns = @(
    "param\s+namePrefix\s+string\s*=\s*'ekip'",
    "param\s+nameSuffix\s+string\s*=\s*'01'",
    "param\s+resourceGroupName\s+string\s*=\s*'rg-ekip-demo'",
    "param\s+uniqueSuffix\s+string\s*=\s*''",
    "'\$\{namePrefix\}-kv-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-cosmos-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-search-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-sb-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-law-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-acaenv-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-backend-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-worker-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-frontend-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-acr-\$\{nameSuffix\}'",
    "'\$\{namePrefix\}-st-\$\{nameSuffix\}'"
)

$check5Passed = $true
foreach ($pattern in $requiredMainPatterns) {
    if (-not [regex]::IsMatch($mainText, $pattern)) {
        Write-Info "main.bicep missing pattern: $pattern"
        $check5Passed = $false
    }
}

try {
    $paramsJson = Get-Content -Path $paramsPath -Raw | ConvertFrom-Json
    if ($paramsJson.parameters.location.value -ne "westeurope") { $check5Passed = $false; Write-Info "demo.parameters.json location must be westeurope." }
    if ($paramsJson.parameters.resourceGroupName.value -ne "rg-ekip-demo") { $check5Passed = $false; Write-Info "demo.parameters.json resourceGroupName must be rg-ekip-demo." }
    if ($paramsJson.parameters.namePrefix.value -ne "ekip") { $check5Passed = $false; Write-Info "demo.parameters.json namePrefix must be ekip." }
    if ($paramsJson.parameters.nameSuffix.value -ne "01") { $check5Passed = $false; Write-Info "demo.parameters.json nameSuffix must be 01." }
    if ($paramsJson.parameters.uniqueSuffix.value -ne "") { $check5Passed = $false; Write-Info "demo.parameters.json uniqueSuffix must default to empty string." }
    if ($paramsJson.parameters.deployApps.value -ne $false) { $check5Passed = $false; Write-Info "demo.parameters.json deployApps must be false." }
    if ($paramsJson.parameters.deployModels.value -ne $true) { $check5Passed = $false; Write-Info "demo.parameters.json deployModels must be true." }
}
catch {
    Write-Info "Unable to parse demo.parameters.json. $($_.Exception.Message)"
    $check5Passed = $false
}

if (($docText -notmatch "uniqueSuffix") -or ($docText -notmatch "ACR") -or ($docText -notmatch "Storage")) {
    Write-Info "DEPLOYMENT_STEPS_0_1.md must document uniqueSuffix handling for ACR/Storage collisions."
    $check5Passed = $false
}

if ($check5Passed) {
    Write-Pass "Naming convention is deterministic and aligned to ekip-<resource>-01."
}
else {
    Write-Fail "Naming convention check failed."
    Write-Host "Remediation: keep naming params deterministic, keep demo.parameters.json aligned, and document uniqueSuffix for global-name collisions."
}

Write-Section "Stop-ship result"
if ($script:AnyFailure) {
    Write-Fail "One or more stop-ship checks failed."
    exit 1
}

Write-Pass "All stop-ship checks passed."
exit 0
