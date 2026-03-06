[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. "$PSScriptRoot/_vars.ps1"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$outDir = Join-Path $repoRoot "infra\out"
$infraOutputsFile = Join-Path $outDir "infra.outputs.json"
$kvSecretsOutFile = Join-Path $outDir "kv.secrets.json"

if (-not (Test-Path -Path $outDir -PathType Container)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

function Get-PlainTextFromSecureString {
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureValue
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-RequiredSecretValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvVarName,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        [ScriptBlock]$FallbackResolver
    )

    $value = "$([Environment]::GetEnvironmentVariable($EnvVarName))".Trim()
    $source = "env var $EnvVarName"

    if ([string]::IsNullOrWhiteSpace($value) -and $null -ne $FallbackResolver) {
        try {
            $candidate = "$(& $FallbackResolver)".Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $value = $candidate
                $source = "azure query"
            }
        }
        catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        $secureValue = Read-Host -Prompt "Enter $DisplayName" -AsSecureString
        $value = (Get-PlainTextFromSecureString -SecureValue $secureValue).Trim()
        $source = "secure prompt"
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Secret value for '$DisplayName' was not provided."
    }

    return [pscustomobject]@{
        Value = $value
        Source = $source
    }
}

function Get-KeyVaultName {
    $nameFromOutputs = $null

    if (Test-Path -Path $infraOutputsFile -PathType Leaf) {
        try {
            $infraOutputs = Get-Content -Path $infraOutputsFile -Raw | ConvertFrom-Json
            if ($infraOutputs.PSObject.Properties.Name -contains "keyVaultName") {
                $nameFromOutputs = [string]$infraOutputs.keyVaultName.value
            }
        }
        catch {
            Write-Host "Could not parse $infraOutputsFile. Falling back to Azure queries."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($nameFromOutputs)) {
        return $nameFromOutputs
    }

    try {
        $defaultKvRaw = az keyvault show --resource-group $ResourceGroupName --name $KeyVaultName --query name -o tsv 2>$null
        $defaultKv = "$defaultKvRaw".Trim()
        if (-not [string]::IsNullOrWhiteSpace($defaultKv)) {
            return $defaultKv
        }
    }
    catch {
    }

    $kvFromListRaw = az resource list --resource-group $ResourceGroupName --resource-type "Microsoft.KeyVault/vaults" --query "[0].name" -o tsv 2>$null
    $kvFromList = "$kvFromListRaw".Trim()
    if (-not [string]::IsNullOrWhiteSpace($kvFromList)) {
        return $kvFromList
    }

    throw "Unable to resolve Key Vault name from outputs or Azure. Run 03_deploy_infra_baseline.ps1 first."
}

function Get-InfraOutputsObject {
    if (-not (Test-Path -Path $infraOutputsFile -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -Path $infraOutputsFile -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-InfraOutputValue {
    param(
        [AllowNull()]
        [object]$InfraOutputs,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InfraOutputs) {
        return ""
    }

    if ($InfraOutputs.PSObject.Properties.Name -contains $Name) {
        return "$($InfraOutputs.$Name.value)".Trim()
    }

    return ""
}

function Invoke-AzTsv {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    try {
        $raw = az @Args 2>$null
        return "$raw".Trim()
    }
    catch {
        return ""
    }
}

function Get-OpenAiAccountName {
    param(
        [object]$InfraOutputs
    )

    $nameFromOutputs = Get-InfraOutputValue -InfraOutputs $InfraOutputs -Name "openAiAccountName"
    if (-not [string]::IsNullOrWhiteSpace($nameFromOutputs)) {
        return $nameFromOutputs
    }

    $nameFromList = Invoke-AzTsv -Args @(
        "cognitiveservices", "account", "list",
        "--resource-group", $ResourceGroupName,
        "--query", "[?kind=='OpenAI'].name | [0]",
        "-o", "tsv"
    )
    if (-not [string]::IsNullOrWhiteSpace($nameFromList)) {
        return $nameFromList
    }

    $expectedName = "$Prefix-openai-$Suffix"
    return (Invoke-AzTsv -Args @(
        "cognitiveservices", "account", "show",
        "--resource-group", $ResourceGroupName,
        "--name", $expectedName,
        "--query", "name",
        "-o", "tsv"
    ))
}

function Get-CosmosPrimaryKey {
    param(
        [string]$AccountName,
        [string]$KeyVaultName,
        [string]$KeyVaultSecretName
    )

    if ([string]::IsNullOrWhiteSpace($AccountName)) {
        return ""
    }

    $cosmosProvisioningState = Invoke-AzTsv -Args @(
        "cosmosdb", "show",
        "--resource-group", $ResourceGroupName,
        "--name", $AccountName,
        "--query", "provisioningState",
        "-o", "tsv"
    )
    if ($cosmosProvisioningState -ieq "Failed") {
        throw "Cosmos account '$AccountName' is in provisioningState=Failed. Re-run Step 3 with a different Cosmos region (set EKIP_COSMOS_LOCATION), then run Step 4 again."
    }

    # Last non-interactive fallback: reuse existing Key Vault secret value if already set.
    if (-not [string]::IsNullOrWhiteSpace($KeyVaultName) -and -not [string]::IsNullOrWhiteSpace($KeyVaultSecretName)) {
        $existingSecretValue = Invoke-AzTsv -Args @(
            "keyvault", "secret", "show",
            "--vault-name", $KeyVaultName,
            "--name", $KeyVaultSecretName,
            "--query", "value",
            "-o", "tsv"
        )
        if (-not [string]::IsNullOrWhiteSpace($existingSecretValue)) {
            return $existingSecretValue
        }
    }

    $maxAttempts = 20
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $key = Invoke-AzTsv -Args @(
            "cosmosdb", "keys", "list",
            "--resource-group", $ResourceGroupName,
            "--name", $AccountName,
            "--type", "keys",
            "--query", "primaryMasterKey",
            "-o", "tsv"
        )
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            return $key
        }

        $keyNoType = Invoke-AzTsv -Args @(
            "cosmosdb", "keys", "list",
            "--resource-group", $ResourceGroupName,
            "--name", $AccountName,
            "--query", "primaryMasterKey",
            "-o", "tsv"
        )
        if (-not [string]::IsNullOrWhiteSpace($keyNoType)) {
            return $keyNoType
        }

        $keysJson = Invoke-AzTsv -Args @(
            "cosmosdb", "keys", "list",
            "--resource-group", $ResourceGroupName,
            "--name", $AccountName,
            "--type", "keys",
            "-o", "json"
        )
        if (-not [string]::IsNullOrWhiteSpace($keysJson)) {
            try {
                $keysObj = $keysJson | ConvertFrom-Json
                foreach ($prop in @("primaryMasterKey", "primaryReadonlyMasterKey", "primaryReadOnlyMasterKey")) {
                    $candidate = "$($keysObj.$prop)".Trim()
                    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                        return $candidate
                    }
                }
            }
            catch {
            }
        }

        $cosmosConnString = Invoke-AzTsv -Args @(
            "cosmosdb", "keys", "list",
            "--resource-group", $ResourceGroupName,
            "--name", $AccountName,
            "--type", "connection-strings",
            "--query", "connectionStrings[0].connectionString",
            "-o", "tsv"
        )
        if ([string]::IsNullOrWhiteSpace($cosmosConnString)) {
            $cosmosConnString = Invoke-AzTsv -Args @(
                "cosmosdb", "keys", "list",
                "--resource-group", $ResourceGroupName,
                "--name", $AccountName,
                "--query", "connectionStrings[0].connectionString",
                "-o", "tsv"
            )
        }
        if ($cosmosConnString -match "AccountKey=([^;]+)") {
            return $Matches[1].Trim()
        }

        if ($attempt -lt $maxAttempts) {
            Write-Host "Cosmos keys endpoint not ready for '$AccountName' (attempt $attempt/$maxAttempts). Retrying in 15s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 15
        }
    }

    $invokeActionKey = Invoke-AzTsv -Args @(
        "resource", "invoke-action",
        "--action", "listKeys",
        "--resource-group", $ResourceGroupName,
        "--resource-type", "Microsoft.DocumentDB/databaseAccounts",
        "--name", $AccountName,
        "--query", "primaryMasterKey",
        "-o", "tsv"
    )
    if (-not [string]::IsNullOrWhiteSpace($invokeActionKey)) {
        return $invokeActionKey
    }

    $subscriptionId = Invoke-AzTsv -Args @("account", "show", "--query", "id", "-o", "tsv")
    if (-not [string]::IsNullOrWhiteSpace($subscriptionId)) {
        foreach ($apiVersion in @("2024-05-15", "2023-04-15", "2021-04-15")) {
            $listKeysUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DocumentDB/databaseAccounts/$AccountName/listKeys?api-version=$apiVersion"
            $restKey = Invoke-AzTsv -Args @(
                "rest",
                "--method", "post",
                "--url", $listKeysUrl,
                "--query", "primaryMasterKey",
                "-o", "tsv"
            )
            if (-not [string]::IsNullOrWhiteSpace($restKey)) {
                return $restKey
            }
        }
    }

    $diagFile = New-TemporaryFile
    $diagMessage = ""
    try {
        $null = az cosmosdb keys list --resource-group $ResourceGroupName --name $AccountName --type keys --query primaryMasterKey -o tsv 2> $diagFile
        $diagMessage = (Get-Content -Path $diagFile -Raw).Trim()
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($diagMessage)) {
            $diagMessage = "$($_.Exception.Message)".Trim()
        }
    }
    finally {
        Remove-Item -Path $diagFile -Force -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrWhiteSpace($diagMessage)) {
        Write-Warning "Cosmos listKeys diagnostic: $diagMessage"
    }

    Write-Warning "Could not auto-resolve Cosmos key for account '$AccountName'. Ensure you have 'Microsoft.DocumentDB/databaseAccounts/listKeys/action' permission (for example, Contributor on '$ResourceGroupName')."
    return ""
}

Write-Section "Step 4 - Set Key Vault secrets"

$keyVaultName = Get-KeyVaultName
Write-Host "Using Key Vault: $keyVaultName"

$infraOutputs = Get-InfraOutputsObject
$searchServiceName = Get-InfraOutputValue -InfraOutputs $infraOutputs -Name "searchServiceName"
if ([string]::IsNullOrWhiteSpace($searchServiceName)) { $searchServiceName = $SearchName }

$serviceBusNamespaceName = Get-InfraOutputValue -InfraOutputs $infraOutputs -Name "serviceBusName"
if ([string]::IsNullOrWhiteSpace($serviceBusNamespaceName)) { $serviceBusNamespaceName = $ServiceBusName }

$storageAccountName = Get-InfraOutputValue -InfraOutputs $infraOutputs -Name "storageAccountName"
if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
    $storageBaseName = ("$Prefix-st-$Suffix".ToLowerInvariant() -replace "-", "")
    $storageAccountName = Invoke-AzTsv -Args @(
        "storage", "account", "list",
        "--resource-group", $ResourceGroupName,
        "--query", "[?starts_with(name, '$storageBaseName')].name | [0]",
        "-o", "tsv"
    )
}
if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
    $storageAccountName = Invoke-AzTsv -Args @(
        "storage", "account", "list",
        "--resource-group", $ResourceGroupName,
        "--query", "[0].name",
        "-o", "tsv"
    )
}
if ([string]::IsNullOrWhiteSpace($storageAccountName)) { $storageAccountName = ($StorageName.ToLowerInvariant() -replace "-", "") }

$cosmosAccountName = Get-InfraOutputValue -InfraOutputs $infraOutputs -Name "cosmosAccountName"
if ([string]::IsNullOrWhiteSpace($cosmosAccountName)) {
    $cosmosBaseName = "$Prefix-cosmos-$Suffix"
    $cosmosAccountName = Invoke-AzTsv -Args @(
        "cosmosdb", "list",
        "--resource-group", $ResourceGroupName,
        "--query", "[?name=='$cosmosBaseName'].name | [0]",
        "-o", "tsv"
    )
}
if ([string]::IsNullOrWhiteSpace($cosmosAccountName)) {
    $cosmosAccountName = Invoke-AzTsv -Args @(
        "cosmosdb", "list",
        "--resource-group", $ResourceGroupName,
        "--query", "[0].name",
        "-o", "tsv"
    )
}
if ([string]::IsNullOrWhiteSpace($cosmosAccountName)) { $cosmosAccountName = $CosmosName }

$secretMap = @(
    [pscustomobject]@{
        outputField = "openaiApiKeySecretId"
        keyVaultSecretName = "ekip-openai-api-key"
        envVar = "EKIP_SECRET_OPENAI_API_KEY"
        prompt = "EKIP OpenAI API key (ekip-openai-api-key)"
        fallbackResolver = {
            $openAiName = Get-OpenAiAccountName -InfraOutputs $infraOutputs
            if ([string]::IsNullOrWhiteSpace($openAiName)) { return "" }
            return (Invoke-AzTsv -Args @(
                "cognitiveservices", "account", "keys", "list",
                "--resource-group", $ResourceGroupName,
                "--name", $openAiName,
                "--query", "key1",
                "-o", "tsv"
            ))
        }
    },
    [pscustomobject]@{
        outputField = "searchAdminKeySecretId"
        keyVaultSecretName = "ekip-search-admin-key"
        envVar = "EKIP_SECRET_SEARCH_ADMIN_KEY"
        prompt = "EKIP Search admin key (ekip-search-admin-key)"
        fallbackResolver = {
            if ([string]::IsNullOrWhiteSpace($searchServiceName)) { return "" }
            return (Invoke-AzTsv -Args @(
                "search", "admin-key", "show",
                "--resource-group", $ResourceGroupName,
                "--service-name", $searchServiceName,
                "--query", "primaryKey",
                "-o", "tsv"
            ))
        }
    },
    [pscustomobject]@{
        outputField = "serviceBusConnStringSecretId"
        keyVaultSecretName = "ekip-servicebus-connection-string"
        envVar = "EKIP_SECRET_SERVICEBUS_CONNECTION_STRING"
        prompt = "EKIP Service Bus connection string (ekip-servicebus-connection-string)"
        fallbackResolver = {
            if ([string]::IsNullOrWhiteSpace($serviceBusNamespaceName)) { return "" }
            return (Invoke-AzTsv -Args @(
                "servicebus", "namespace", "authorization-rule", "keys", "list",
                "--resource-group", $ResourceGroupName,
                "--namespace-name", $serviceBusNamespaceName,
                "--name", "RootManageSharedAccessKey",
                "--query", "primaryConnectionString",
                "-o", "tsv"
            ))
        }
    },
    [pscustomobject]@{
        outputField = "storageConnStringSecretId"
        keyVaultSecretName = "ekip-storage-connection-string"
        envVar = "EKIP_SECRET_STORAGE_CONNECTION_STRING"
        prompt = "EKIP Storage connection string (ekip-storage-connection-string)"
        fallbackResolver = {
            if ([string]::IsNullOrWhiteSpace($storageAccountName)) { return "" }
            return (Invoke-AzTsv -Args @(
                "storage", "account", "show-connection-string",
                "--resource-group", $ResourceGroupName,
                "--name", $storageAccountName,
                "--query", "connectionString",
                "-o", "tsv"
            ))
        }
    },
    [pscustomobject]@{
        outputField = "cosmosKeySecretId"
        keyVaultSecretName = "ekip-cosmos-key"
        envVar = "EKIP_SECRET_COSMOS_KEY"
        prompt = "EKIP Cosmos key (ekip-cosmos-key)"
        fallbackResolver = {
            return (Get-CosmosPrimaryKey -AccountName $cosmosAccountName -KeyVaultName $keyVaultName -KeyVaultSecretName "ekip-cosmos-key")
        }
    }
)

$secretIds = [ordered]@{}
foreach ($item in $secretMap) {
    $resolved = Get-RequiredSecretValue -EnvVarName $item.envVar -DisplayName $item.prompt -FallbackResolver $item.fallbackResolver
    Write-Host "Setting secret '$($item.keyVaultSecretName)' from $($resolved.Source)..."
    az keyvault secret set --vault-name $keyVaultName --name $item.keyVaultSecretName --value $resolved.Value --only-show-errors | Out-Null

    $secretId = (az keyvault secret show --vault-name $keyVaultName --name $item.keyVaultSecretName --query id -o tsv).Trim()
    if ([string]::IsNullOrWhiteSpace($secretId)) {
        throw "Could not resolve secret id for '$($item.keyVaultSecretName)'."
    }

    $secretIds[$item.outputField] = $secretId
}

$secretIds | ConvertTo-Json -Depth 10 | Set-Content -Path $kvSecretsOutFile -Encoding utf8
Write-Host "Secret IDs written to: $kvSecretsOutFile"
