# Build and push SRE demo container images to ACR, then update the Container App and Job.
# Uses 'az acr build' (server-side build — no local Docker required).
#
# Images:
#   sre-api     - Python FastAPI Order Management API  (apps/api/)
#   sre-loadgen - Synthetic load generator             (apps/loadgen/)
#
# Usage:
#   .\Deploy-Containers.ps1 -ContainerRegistryName <acr> -ResourceGroupName <rg> `
#       -BackendAppName <ca-name> -LoadGenJobName <job-name>

param (
    [Parameter(Mandatory=$true)]
    [string]$ContainerRegistryName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$BackendAppName,

    [Parameter(Mandatory=$true)]
    [string]$LoadGenJobName,

    [Parameter(Mandatory=$false)]
    [ValidateSet("sre-api", "sre-loadgen")]
    [string[]]$Images = @("sre-api", "sre-loadgen"),

    [Parameter(Mandatory=$false)]
    [string]$Tag = "latest"
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== SRE Demo: Build & Push Container Images ===" -ForegroundColor Cyan
Write-Host "  Registry       : $ContainerRegistryName" -ForegroundColor White
Write-Host "  Resource Group : $ResourceGroupName"     -ForegroundColor White
Write-Host "  Tag            : $Tag"                   -ForegroundColor White

$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8      = '1'
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding          = [System.Text.Encoding]::UTF8

$repoRoot  = (Resolve-Path "$PSScriptRoot\..").Path
$acrServer = "$ContainerRegistryName.azurecr.io"

$imageConfigs = @{
    "sre-api" = @{
        context    = (Join-Path $repoRoot "apps\api")
        dockerfile = (Join-Path $repoRoot "apps\api\Dockerfile")
        type       = "containerapp"
        name       = $BackendAppName
    }
    "sre-loadgen" = @{
        context    = (Join-Path $repoRoot "apps\loadgen")
        dockerfile = (Join-Path $repoRoot "apps\loadgen\Dockerfile")
        type       = "job"
        name       = $LoadGenJobName
    }
}

$failed = @()

# ── Step 1: Build & push images ──
foreach ($imageName in $Images) {
    $config   = $imageConfigs[$imageName]
    $imageRef = "${imageName}:${Tag}"

    Write-Host "`nBuilding '$imageRef'..." -ForegroundColor Yellow
    Write-Host "  Dockerfile : $($config.dockerfile)" -ForegroundColor Gray
    Write-Host "  Context    : $($config.context)"    -ForegroundColor Gray

    $maxRetries  = 3
    $buildSuccess = $false
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        if ($attempt -gt 1) {
            $delay = $attempt * 30
            Write-Host "  Retry $attempt/$maxRetries in ${delay}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delay
        }

        az acr build `
            --resource-group $ResourceGroupName `
            --registry       $ContainerRegistryName `
            --file           $config.dockerfile `
            --image          $imageRef `
            $config.context

        if ($LASTEXITCODE -eq 0) {
            $buildSuccess = $true
            break
        }
        Write-Host "  Attempt $attempt failed (exit code $LASTEXITCODE)" -ForegroundColor Yellow
    }

    if (-not $buildSuccess) {
        Write-Host "FAILED to build '$imageRef' after $maxRetries attempts" -ForegroundColor Red
        $failed += $imageName
    } else {
        Write-Host "[OK] '$imageRef' pushed to $ContainerRegistryName" -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    throw "The following images failed to build: $($failed -join ', ')"
}

# ── Step 2: Update Container App and Job with new images ──
Write-Host "`n=== Updating Container App and Job ===" -ForegroundColor Cyan

foreach ($imageName in $Images) {
    $config   = $imageConfigs[$imageName]
    $imageUri = "$acrServer/${imageName}:${Tag}"

    Write-Host "  Updating $($config.name) -> $imageUri" -ForegroundColor Yellow

    if ($config.type -eq "containerapp") {
        az containerapp update `
            --name           $config.name `
            --resource-group $ResourceGroupName `
            --image          $imageUri `
            --output         none
    } elseif ($config.type -eq "job") {
        az containerapp job update `
            --name           $config.name `
            --resource-group $ResourceGroupName `
            --image          $imageUri `
            --output         none
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update '$($config.name)'"
    }
    Write-Host "  [OK] $($config.name) updated" -ForegroundColor Green
}

Write-Host "`n[OK] All images built, pushed, and resources updated." -ForegroundColor Green
