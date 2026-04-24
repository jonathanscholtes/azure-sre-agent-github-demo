<#
.SYNOPSIS
    Start the Azure SRE Agent closed-loop reliability demo.

.DESCRIPTION
    Reads Terraform outputs, injects a bug into the running API, floods Application
    Insights with errors, then prints a presenter guide with direct portal deep-links.

    The closed-loop continues automatically:
      Errors → SRE Agent investigates → ADO bug filed → GitHub Copilot opens fix PR
      → Human reviews and merges → CI/CD deploys clean code

    Prerequisites:
      - Infrastructure already deployed (deploy.ps1 completed)
      - 'az login' authenticated to the correct subscription
      - Terraform state accessible (cd infra; terraform output works)

.PARAMETER Bug
    Which bug to inject. Defaults to "Random".
    Valid values: KeyError, AttributeError, Random

.PARAMETER LoadCount
    Number of orders to create+process in the initial error burst. Defaults to 20.

.EXAMPLE
    .\tools\Start-SreDemo.ps1

.EXAMPLE
    .\tools\Start-SreDemo.ps1 -Bug KeyError -LoadCount 30
#>

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("KeyError", "AttributeError", "Random")]
    [string]$Bug = "Random",

    [Parameter(Mandatory=$false)]
    [int]$LoadCount = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot  = (Resolve-Path "$PSScriptRoot\..").Path
$infraDir  = Join-Path $repoRoot "infra"
$toolsDir  = Join-Path $repoRoot "tools"
$stateFile = Join-Path $repoRoot ".chaos-state"

# ── Guard: already in chaos state ─────────────────────────────────────────────
if (Test-Path $stateFile) {
    $existing = Get-Content $stateFile -Raw | ConvertFrom-Json
    Write-Host ""
    Write-Host "WARNING: Bug '$($existing.Bug)' is already active (injected at $($existing.AppliedAt))." -ForegroundColor Yellow
    Write-Host "         Run Invoke-ChaosBug.ps1 -Revert to clean up before restarting the demo." -ForegroundColor Yellow
    exit 1
}

# ── Step 1: Read Terraform outputs ────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Azure SRE Agent Demo — Start" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Reading Terraform outputs..." -ForegroundColor Yellow

Push-Location $infraDir
$tf = terraform output -json | ConvertFrom-Json
Pop-Location

$acrName           = $tf.container_registry_name.value
$resourceGroupName = $tf.resource_group_name.value
$backendAppName    = $tf.backend_container_app_name.value
$backendUrl        = $tf.backend_container_app_url.value
$appInsightsName   = $tf.application_insights_name.value
$appInsightsId     = $tf.application_insights_id.value
$sreAgentPortalUrl = $tf.sre_agent_portal_url.value

Write-Host "  ACR              : $acrName"            -ForegroundColor Gray
Write-Host "  Resource Group   : $resourceGroupName"  -ForegroundColor Gray
Write-Host "  API App          : $backendAppName"     -ForegroundColor Gray
Write-Host "  API URL          : $backendUrl"         -ForegroundColor Gray
Write-Host "  App Insights     : $appInsightsName"    -ForegroundColor Gray

# ── Step 2: Inject bug + build + deploy ───────────────────────────────────────
Write-Host ""
Write-Host "Injecting bug into API..." -ForegroundColor Red

& "$toolsDir\Invoke-ChaosBug.ps1" `
    -Bug                   $Bug `
    -ContainerRegistryName $acrName `
    -ResourceGroupName     $resourceGroupName `
    -BackendAppName        $backendAppName

if ($LASTEXITCODE -ne 0) {
    Write-Host "Bug injection failed." -ForegroundColor Red
    exit 1
}

# Read back which bug was chosen (Invoke-ChaosBug writes .chaos-state)
$chosenBug = (Get-Content $stateFile -Raw | ConvertFrom-Json).Bug

# ── Step 3: Wait for new revision to become healthy ───────────────────────────
Write-Host ""
Write-Host "Waiting for new revision to become healthy..." -ForegroundColor Yellow
$maxWait = 120; $waited = 0; $interval = 10; $ready = $false

while (-not $ready -and $waited -lt $maxWait) {
    try {
        $health = Invoke-RestMethod -Uri "$backendUrl/health" -Method GET -TimeoutSec 8 -ErrorAction Stop
        if ($health.status -eq "healthy") { $ready = $true }
    } catch { }
    if (-not $ready) {
        Write-Host "  Still starting... (${waited}s)" -ForegroundColor Gray
        Start-Sleep -Seconds $interval
        $waited += $interval
    }
}

if (-not $ready) {
    Write-Host "WARNING: API health check timed out after ${maxWait}s — proceeding anyway." -ForegroundColor Yellow
}

# ── Step 4: Burst load to generate immediate errors ───────────────────────────
Write-Host ""
Write-Host "Generating $LoadCount orders to produce errors in Application Insights..." -ForegroundColor Yellow

try {
    $result = Invoke-RestMethod `
        -Uri     "$backendUrl/api/demo/simulate-load?orders=$LoadCount" `
        -Method  POST `
        -TimeoutSec 60 `
        -ErrorAction Stop
    Write-Host "  [OK] Load burst complete: $($result | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch {
    # Errors are expected — the bug causes the API to return 500s
    Write-Host "  [OK] Errors returned from API — this is expected with the bug active." -ForegroundColor Green
}

# ── Step 5: Build deep-link URLs ──────────────────────────────────────────────
# Application Insights Failures blade
$encodedId         = [Uri]::EscapeDataString($appInsightsId)
$appInsightsFailuresUrl = "https://portal.azure.com/#blade/AppInsightsExtension/FailuresCuratedFrameBlade/ComponentId/$encodedId"

# ── Step 6: Presenter guide ───────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Red
Write-Host "  BUG ACTIVE: $chosenBug" -ForegroundColor Red
Write-Host "  Errors are now flowing into Application Insights." -ForegroundColor Red
Write-Host "============================================================" -ForegroundColor Red
Write-Host ""
Write-Host "PRESENTER STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [1] Open Application Insights — Failures blade:" -ForegroundColor Cyan
Write-Host "      $appInsightsFailuresUrl" -ForegroundColor White
Write-Host ""
Write-Host "      Show: error rate spike, exception type ($chosenBug)," -ForegroundColor Gray
Write-Host "            stack trace, affected operations" -ForegroundColor Gray
Write-Host ""

if ($sreAgentPortalUrl) {
    Write-Host "  [2] Open SRE Agent:" -ForegroundColor Cyan
    Write-Host "      $sreAgentPortalUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "      Show: agent investigating the error pattern," -ForegroundColor Gray
    Write-Host "            root-cause summary, ADO bug being filed" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "  [2] SRE Agent not deployed (enable_sre_agent = false in terraform.tfvars)" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host "  [3] Open Azure DevOps Boards:" -ForegroundColor Cyan
Write-Host "      Show the auto-created bug with SRE Agent investigation notes" -ForegroundColor Gray
Write-Host ""
Write-Host "  [4] Open GitHub — Copilot coding agent:" -ForegroundColor Cyan
Write-Host "      Show Copilot reading the ADO bug, creating a fix branch, opening PR" -ForegroundColor Gray
Write-Host ""
Write-Host "  [5] Review and merge the PR — this is the human gate." -ForegroundColor Cyan
Write-Host "      CI/CD deploys the fix; errors stop automatically." -ForegroundColor Gray
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  After the demo, reset the environment:" -ForegroundColor Green
Write-Host ""
Write-Host "  .\tools\Invoke-ChaosBug.ps1 -Revert ``" -ForegroundColor White
Write-Host "      -ContainerRegistryName $acrName ``" -ForegroundColor White
Write-Host "      -ResourceGroupName     $resourceGroupName ``" -ForegroundColor White
Write-Host "      -BackendAppName        $backendAppName" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
