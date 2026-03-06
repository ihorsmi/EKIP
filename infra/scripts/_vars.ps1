$Prefix = "ekip"
$Suffix = "01"
$ResourceGroupName = "rg-ekip-demo"
$Location = if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { "westeurope" }
$CosmosLocation = if ($env:EKIP_COSMOS_LOCATION) { $env:EKIP_COSMOS_LOCATION } else { $Location }
$AppsLocation = if ($env:EKIP_APPS_LOCATION) { $env:EKIP_APPS_LOCATION } else { $Location }
$DeployModels = if ($env:EKIP_DEPLOY_MODELS) { $env:EKIP_DEPLOY_MODELS.ToLowerInvariant() } else { "false" }

$AcrName = "$Prefix-acr-$Suffix"
$KeyVaultName = "$Prefix-kv-$Suffix"
$CosmosName = "$Prefix-cosmos-$Suffix"
$SearchName = "$Prefix-search-$Suffix"
$ServiceBusName = "$Prefix-sb-$Suffix"
$StorageName = "$Prefix-st-$Suffix"
$LogAnalyticsName = "$Prefix-law-$Suffix"
$ContainerAppsEnvName = "$Prefix-acaenv-$Suffix"
$BackendAppName = "$Prefix-backend-$Suffix"
$WorkerAppName = "$Prefix-worker-$Suffix"
$FrontendAppName = "$Prefix-frontend-$Suffix"

function Write-Section {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}
