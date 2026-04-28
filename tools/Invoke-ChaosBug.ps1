<#
.SYNOPSIS
    Introduce (or revert) a realistic application bug to drive the Azure SRE Agent demo.

.DESCRIPTION
    Patches one of several realistic code bugs into the Order Management API source,
    then optionally builds and deploys the patched image directly via 'az acr build'
    so you don't need a CI pipeline.

    Active bug state is tracked in .chaos-state at the repo root (not committed to git).
    Run with -Revert to restore the clean source and optionally redeploy.

.PARAMETER Bug
    Which bug to introduce. Defaults to "Random".
      KeyError      - renames field key in build_line_item_summary:
                      item["unit_price"] -> item["price"]
                      Effect: KeyError on every POST /api/orders/{id}/process
      AttributeError - accesses wrong attribute in create_order:
                       req.line_items -> req.lineItems
                       Effect: AttributeError on every POST /api/orders

.PARAMETER Revert
    Restore the original source (reads bug name from .chaos-state).

.PARAMETER ContainerRegistryName
    ACR name. When supplied together with ResourceGroupName and BackendAppName,
    the patched image is built and deployed immediately via 'az acr build'.

.PARAMETER ResourceGroupName
    Resource group containing the ACR and Container App.

.PARAMETER BackendAppName
    Name of the Container App to update.

.PARAMETER Tag
    Image tag to push. Defaults to "chaos" so it does not overwrite "latest".

.EXAMPLE
    # Introduce a random bug and redeploy
    .\tools\Invoke-ChaosBug.ps1 `
        -ContainerRegistryName acrmyacr `
        -ResourceGroupName     rg-sre-dev-eastus2-abc12345 `
        -BackendAppName        ca-api-sre-abc12345

.EXAMPLE
    # Revert the bug and redeploy clean
    .\tools\Invoke-ChaosBug.ps1 -Revert `
        -ContainerRegistryName acrmyacr `
        -ResourceGroupName     rg-sre-dev-eastus2-abc12345 `
        -BackendAppName        ca-api-sre-abc12345

.PARAMETER SkipDeploy
    Patch the source but skip the ACR build and Container App update.
    Use this when you want GitHub Actions CI/CD to handle the deployment instead.

.EXAMPLE
    # Apply a specific bug without redeploying (push to git to trigger CI instead)
    .\tools\Invoke-ChaosBug.ps1 -Bug KeyError

.EXAMPLE
    # Apply a bug and skip ACR deploy (let GitHub Actions CI/CD deploy it)
    .\tools\Invoke-ChaosBug.ps1 -SkipDeploy `
        -ContainerRegistryName acrmyacr `
        -ResourceGroupName     rg-sre-dev-eastus2-abc12345 `
        -BackendAppName        ca-api-sre-abc12345
#>

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("KeyError", "AttributeError", "Random")]
    [string]$Bug = "Random",

    [switch]$Revert,

    [switch]$SkipDeploy,

    [Parameter(Mandatory=$false)]
    [string]$ContainerRegistryName = "",

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",

    [Parameter(Mandatory=$false)]
    [string]$BackendAppName = "",

    [Parameter(Mandatory=$false)]
    [string]$Tag = "chaos"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot   = (Resolve-Path "$PSScriptRoot\..").Path
$stateFile  = Join-Path $repoRoot ".chaos-state"
$ordersFile = Join-Path $repoRoot "apps\api\app\routes\orders.py"

# ── Bug catalogue ──────────────────────────────────────────────────────────────
# Each entry: File, Clean (original text), Buggy (patched text), Description, ErrorType
# Bugs are placed in route handlers - outside the store's try/except - so they
# always propagate as HTTP 500 and appear in Application Insights.

$bugCatalogue = [ordered]@{

    # Renames the field key used in build_line_item_summary.
    # item["unit_price"] is the correct key written by LineItem.model_dump();
    # item["price"] does not exist -> KeyError on every /process call.
    "KeyError" = @{
        Description = "Renamed field key 'unit_price' to 'price' in build_line_item_summary"
        File        = $ordersFile
        Clean       = '    total = item["unit_price"] * item["quantity"]'
        Buggy       = '    total = item["price"] * item["quantity"]'
        ErrorType   = "KeyError: 'price'"
        Endpoint    = "POST /api/orders/{id}/process"
    }

    # Accesses req.lineItems instead of the correct Pydantic field req.line_items
    # in the create_order handler -> AttributeError on every order creation.
    "AttributeError" = @{
        Description = "Accessed req.lineItems instead of req.line_items in create_order"
        File        = $ordersFile
        Clean       = '        "lineItems": [item.model_dump() for item in req.line_items],'
        Buggy       = '        "lineItems": [item.model_dump() for item in req.lineItems],'
        ErrorType   = "AttributeError: 'CreateOrderRequest' object has no attribute 'lineItems'"
        Endpoint    = "POST /api/orders"
    }
}

# ── Helpers ────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Msg, [string]$Color = "Cyan")
    Write-Host $Msg -ForegroundColor $Color
}

function Read-StateFile {
    if (Test-Path $stateFile) {
        return Get-Content $stateFile -Raw | ConvertFrom-Json
    }
    return $null
}

function Invoke-AcrDeploy {
    Write-Step "`n=== Building and deploying image ===" "Cyan"

    $acrServer  = "$ContainerRegistryName.azurecr.io"
    $imageRef   = "sre-api:$Tag"
    $dockerfile = Join-Path $repoRoot "apps\api\Dockerfile"
    $context    = Join-Path $repoRoot "apps\api"

    Write-Step "  Building $imageRef in ACR $ContainerRegistryName..." "Yellow"
    az acr build `
        --resource-group $ResourceGroupName `
        --registry       $ContainerRegistryName `
        --file           $dockerfile `
        --image          $imageRef `
        $context

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ACR build failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }

    Write-Step "  Updating $BackendAppName -> $acrServer/$imageRef..." "Yellow"
    az containerapp update `
        --name           $BackendAppName `
        --resource-group $ResourceGroupName `
        --image          "$acrServer/$imageRef" `
        --output         none

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Container app update failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }

    Write-Step "[OK] Deployed $imageRef to $BackendAppName" "Green"
}

$canDeploy = ($ContainerRegistryName -and $ResourceGroupName -and $BackendAppName) -and (-not $SkipDeploy)

# ══════════════════════════════════════════════════════════════════════════════
# REVERT
# ══════════════════════════════════════════════════════════════════════════════
if ($Revert) {
    $state = Read-StateFile
    if (-not $state) {
        Write-Host "No active chaos bug found (.chaos-state does not exist)." -ForegroundColor Yellow
        exit 0
    }

    $bugName = $state.Bug
    $def     = $bugCatalogue[$bugName]

    Write-Step "`n=== Reverting bug: $bugName ===" "Cyan"
    Write-Host "  Applied at : $($state.AppliedAt)"
    Write-Host "  File       : $($def.File)"

    $content = [System.IO.File]::ReadAllText($def.File)

    if (-not $content.Contains($def.Buggy)) {
        Write-Host "  Buggy pattern not found - file may already be clean." -ForegroundColor Yellow
    } else {
        $clean = $content.Replace($def.Buggy, $def.Clean)
        [System.IO.File]::WriteAllText($def.File, $clean, [System.Text.Encoding]::UTF8)
        Write-Step "[OK] Source restored: $($def.File | Split-Path -Leaf)" "Green"
    }

    Remove-Item $stateFile -Force
    Write-Step "[OK] .chaos-state cleared" "Green"

    if ($canDeploy) {
        Invoke-AcrDeploy
        Write-Step "`nClean image deployed. Errors should stop within ~1 minute." "Green"
    } else {
        Write-Host "`nDeploy skipped - push to git or run Deploy-Containers.ps1 to apply." -ForegroundColor Gray
    }

    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
# INTRODUCE BUG
# ══════════════════════════════════════════════════════════════════════════════
$existing = Read-StateFile
if ($existing) {
    Write-Host "WARNING: Bug '$($existing.Bug)' is already active (applied at $($existing.AppliedAt))." -ForegroundColor Yellow
    Write-Host "         Run with -Revert first." -ForegroundColor Yellow
    exit 1
}

$bugName = if ($Bug -eq "Random") { ($bugCatalogue.Keys | Get-Random) } else { $Bug }
$def     = $bugCatalogue[$bugName]

Write-Step "`n=== Introducing bug: $bugName ===" "Red"
Write-Host "  Description : $($def.Description)"
Write-Host "  Fires on    : $($def.Endpoint)"
Write-Host "  Error type  : $($def.ErrorType)"
Write-Host "  File        : $($def.File)"

$content = [System.IO.File]::ReadAllText($def.File)

if (-not $content.Contains($def.Clean)) {
    Write-Error "Expected clean pattern not found in $($def.File | Split-Path -Leaf). Has the file been manually modified?"
}

$patched = $content.Replace($def.Clean, $def.Buggy)
[System.IO.File]::WriteAllText($def.File, $patched, [System.Text.Encoding]::UTF8)

$state = [PSCustomObject]@{
    Bug       = $bugName
    AppliedAt = (Get-Date -Format "o")
} | ConvertTo-Json
Set-Content -Path $stateFile -Value $state -Encoding UTF8

Write-Step "[OK] Patch applied: $($def.File | Split-Path -Leaf)" "Green"

if ($canDeploy) {
    Invoke-AcrDeploy
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "  Bug deployed: $bugName"                                       -ForegroundColor Red
    Write-Host "  $($def.ErrorType)"                                            -ForegroundColor Red
    Write-Host "  Fires on every: $($def.Endpoint)"                            -ForegroundColor Red
    Write-Host ""                                                               -ForegroundColor Red
    Write-Host "  Errors will appear in Application Insights in ~2 minutes."   -ForegroundColor Red
    Write-Host "  Trigger load: POST <api-url>/api/demo/simulate-load"         -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "Deploy skipped - no ACR/RG/App params provided." -ForegroundColor Gray
    Write-Host "Commit and push, or run:" -ForegroundColor Gray
    Write-Host "  .\scripts\Deploy-Containers.ps1 -Images sre-api ..." -ForegroundColor Gray
}
