# Azure SRE Demo - Main Deployment Orchestrator
#
# Usage:
#   Deploy:               .\deploy.ps1 -Subscription '<name-or-id>'
#   Re-run (skip init):   .\deploy.ps1 -Subscription '<name-or-id>' -SkipBootstrap
#   Destroy:              .\deploy.ps1 -Subscription '<name-or-id>' -Destroy
#   Deploy + GitHub OIDC: .\deploy.ps1 -Subscription '<name-or-id>' -SetupGitHub

param (
    [Parameter(Mandatory=$true)]
    [string]$Subscription,

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",

    [switch]$SkipBootstrap,
    [switch]$Destroy,
    [switch]$SetupGitHub
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsDir = Join-Path $PSScriptRoot "scripts"

Import-Module (Join-Path $scriptsDir "common/DeploymentFunctions.psm1") -Force

Write-Host @"

============================================================
  Azure SRE Closed-Loop Demo - Deployment Orchestrator
============================================================

"@ -ForegroundColor Cyan

Write-Host "Subscription : $Subscription"
Write-Host "Location     : $Location"
Write-Host ""

# --------------------------------------------------------------------------
# AZURE AUTH
# --------------------------------------------------------------------------
Initialize-AzureContext -Subscription $Subscription

$subscriptionId = az account show --query id -o tsv
Write-Host "Connected to subscription: $subscriptionId" -ForegroundColor Green

# --------------------------------------------------------------------------
# PHASE 0: Bootstrap Terraform remote state backend
# --------------------------------------------------------------------------
$suffix               = (($subscriptionId -replace '-', '').Substring(0, 8)).ToLower()
$TfStateStorageAccount = "stotfsre$suffix"
$TfStateResourceGroup  = "rg-tfstate-sre"

if ($Destroy -or $SkipBootstrap) {
    Write-Host "`n=== PHASE 0: Skipped ===" -ForegroundColor DarkGray
} else {
    Write-Host "`n=== PHASE 0: Terraform State Backend Bootstrap ===" -ForegroundColor Magenta
    Write-Host "  Resource group : $TfStateResourceGroup"  -ForegroundColor Cyan
    Write-Host "  Storage account: $TfStateStorageAccount" -ForegroundColor Cyan

    az group create `
        --name $TfStateResourceGroup `
        --location $Location `
        --output none

    az storage account create `
        --name $TfStateStorageAccount `
        --resource-group $TfStateResourceGroup `
        --sku Standard_LRS `
        --allow-blob-public-access false `
        --min-tls-version TLS1_2 `
        --output none

    $currentUserId = az ad signed-in-user show --query id -o tsv 2>$null
    $storageId     = az storage account show `
                         --name $TfStateStorageAccount `
                         --resource-group $TfStateResourceGroup `
                         --query id -o tsv

    if ($currentUserId -and $storageId) {
        Write-Host "  Assigning Storage Blob Data Contributor..." -ForegroundColor Cyan
        az role assignment create `
            --assignee $currentUserId `
            --role "Storage Blob Data Contributor" `
            --scope $storageId `
            --output none 2>&1 | Out-Null

        Write-Host "  Waiting for role assignment to propagate..." -ForegroundColor Gray
        $maxWait = 300; $waited = 0; $interval = 10; $ready = $false
        while (-not $ready -and $waited -lt $maxWait) {
            try {
                $null = az storage container list `
                    --account-name $TfStateStorageAccount `
                    --auth-mode login `
                    --output none `
                    --only-show-errors 2>$null
                if ($LASTEXITCODE -eq 0) { $ready = $true }
            } catch { }
            if (-not $ready) {
                Write-Host "  Still propagating... ($waited s elapsed)" -ForegroundColor Gray
                Start-Sleep -Seconds $interval
                $waited += $interval
            }
        }
        if (-not $ready) {
            Write-Host "WARNING: Role assignment may not have propagated after ${maxWait}s - continuing." -ForegroundColor Yellow
        } else {
            Write-Host "  Role assignment effective after ${waited}s." -ForegroundColor Green
        }
    }

    az storage container create `
        --name tfstate `
        --account-name $TfStateStorageAccount `
        --auth-mode login `
        --output none

    Write-Host "State backend ready." -ForegroundColor Green
}

# --------------------------------------------------------------------------
# PHASE 1: Infrastructure (Terraform)
# --------------------------------------------------------------------------
$action = if ($Destroy) { "destroy" } else { "all" }
Write-Host "`n=== PHASE 1: Infrastructure ($action) ===" -ForegroundColor Magenta

& "$scriptsDir\Deploy-Infrastructure.ps1" `
    -Action               $action `
    -Subscription         $Subscription `
    -Location             $Location `
    -TfStateStorageAccount $TfStateStorageAccount

if ($LASTEXITCODE -ne 0) {
    Write-Host "Infrastructure deployment failed" -ForegroundColor Red
    exit 1
}

if ($Destroy) {
    Write-Host "`nAll resources destroyed." -ForegroundColor Green
    exit 0
}

# --------------------------------------------------------------------------
# Read Terraform outputs
# --------------------------------------------------------------------------
Write-Host "`nReading Terraform outputs..." -ForegroundColor Yellow
Push-Location (Join-Path $PSScriptRoot "infra")
$tfOutputs = terraform output -json | ConvertFrom-Json
Pop-Location

$resourceGroupName  = $tfOutputs.resource_group_name.value
$acrName            = $tfOutputs.container_registry_name.value
$backendAppName     = $tfOutputs.backend_container_app_name.value
$backendUrl         = $tfOutputs.backend_container_app_url.value
$loadgenJobName     = $tfOutputs.load_generator_job_name.value
$cosmosEndpoint     = $tfOutputs.cosmosdb_endpoint.value
$appInsightsName    = $tfOutputs.application_insights_name.value
$sreAgentPortalUrl  = $tfOutputs.sre_agent_portal_url.value

Write-Host "  Resource Group   : $resourceGroupName"  -ForegroundColor Cyan
Write-Host "  ACR              : $acrName"             -ForegroundColor Cyan
Write-Host "  API App          : $backendAppName"      -ForegroundColor Cyan
Write-Host "  Load Gen Job     : $loadgenJobName"      -ForegroundColor Cyan
Write-Host "  App Insights     : $appInsightsName"     -ForegroundColor Cyan
Write-Host "  Cosmos DB        : $cosmosEndpoint"      -ForegroundColor Cyan
if ($sreAgentPortalUrl) {
    Write-Host "  SRE Agent        : $sreAgentPortalUrl" -ForegroundColor Cyan
}

# --------------------------------------------------------------------------
# PHASE 2: Build & Deploy Container Images
# --------------------------------------------------------------------------
Write-Host "`n=== PHASE 2: Container Images ===" -ForegroundColor Magenta

& "$scriptsDir\Deploy-Containers.ps1" `
    -ContainerRegistryName $acrName `
    -ResourceGroupName     $resourceGroupName `
    -BackendAppName        $backendAppName `
    -LoadGenJobName        $loadgenJobName

if ($LASTEXITCODE -ne 0) {
    Write-Host "Container deployment failed" -ForegroundColor Red
    exit 1
}

# --------------------------------------------------------------------------
# PHASE 3: Seed Demo Data
# --------------------------------------------------------------------------
Write-Host "`n=== PHASE 3: Seed Demo Data ===" -ForegroundColor Magenta
Write-Host "  Waiting 30s for the API to become healthy..." -ForegroundColor Gray
Start-Sleep -Seconds 30

$maxAttempts = 12; $attempt = 0; $apiReady = $false
while ($attempt -lt $maxAttempts -and -not $apiReady) {
    try {
        $health = Invoke-RestMethod -Uri "$backendUrl/health" -Method GET -TimeoutSec 10 -ErrorAction Stop
        if ($health.status -eq "healthy") { $apiReady = $true }
    } catch { }
    if (-not $apiReady) {
        Write-Host "  API not ready yet (attempt $($attempt + 1)/$maxAttempts)..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
    }
    $attempt++
}

if ($apiReady) {
    try {
        $seed = Invoke-RestMethod -Uri "$backendUrl/api/demo/seed" -Method POST -TimeoutSec 30 -ErrorAction Stop
        Write-Host "  [OK] $($seed.message)" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Seed request failed: $_ - run POST $backendUrl/api/demo/seed manually" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [WARN] API did not become healthy - seed manually: POST $backendUrl/api/demo/seed" -ForegroundColor Yellow
}

# --------------------------------------------------------------------------
# PHASE 4: GitHub OIDC Setup (optional)
# --------------------------------------------------------------------------
if ($SetupGitHub) {
    Write-Host "`n=== PHASE 4: GitHub OIDC Setup ===" -ForegroundColor Magenta
    & "$scriptsDir\New-GitHubOidc.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "GitHub OIDC setup failed" -ForegroundColor Red
        exit 1
    }
}

# --------------------------------------------------------------------------
# Done
# --------------------------------------------------------------------------
Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host "`nEndpoints:" -ForegroundColor Cyan
Write-Host "  API       : $backendUrl"        -ForegroundColor Cyan
Write-Host "  API Docs  : $backendUrl/docs"   -ForegroundColor Cyan
Write-Host "  Health    : $backendUrl/health" -ForegroundColor Cyan
Write-Host ""
if ($sreAgentPortalUrl) {
    Write-Host "SRE Agent:" -ForegroundColor Magenta
    Write-Host "  $sreAgentPortalUrl" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "NEXT: Open the SRE Agent portal link above and configure:" -ForegroundColor Yellow
    Write-Host "  1. Workflow trigger (Application Insights alert or manual)" -ForegroundColor White
    Write-Host "  2. Bug destination: Azure DevOps org / project / area path" -ForegroundColor White
    Write-Host "  3. Fix destination: GitHub repo for Copilot coding agent PR" -ForegroundColor White
    Write-Host ""
}
Write-Host "SRE Demo steps:" -ForegroundColor Yellow
Write-Host "  1. Inject a bug:   .\tools\Invoke-ChaosBug.ps1 -ContainerRegistryName $acrName -ResourceGroupName $resourceGroupName -BackendAppName $backendAppName" -ForegroundColor White
Write-Host "  2. Generate load:  Invoke-RestMethod '$backendUrl/api/demo/simulate-load' -Method POST" -ForegroundColor White
Write-Host "  3. Watch errors appear in Application Insights '$appInsightsName'" -ForegroundColor White
Write-Host "  4. SRE Agent investigates and files an ADO bug automatically" -ForegroundColor White
  Write-Host "  5. GitHub Copilot opens a fix PR - review and merge" -ForegroundColor White
Write-Host "  6. Revert bug:     .\tools\Invoke-ChaosBug.ps1 -Revert -ContainerRegistryName $acrName -ResourceGroupName $resourceGroupName -BackendAppName $backendAppName" -ForegroundColor White
Write-Host ""
Write-Host "To seed demo data manually:" -ForegroundColor Yellow
Write-Host "  Invoke-RestMethod '$backendUrl/api/demo/seed' -Method POST" -ForegroundColor White
Write-Host ""
Write-Host "To view all outputs: cd infra; terraform output" -ForegroundColor Gray
