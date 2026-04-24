# Deploy Azure Infrastructure using Terraform
#
# Called by the orchestrator (deploy.ps1) or standalone:
#   .\Deploy-Infrastructure.ps1 -Action all -Subscription '<id>'
#   .\Deploy-Infrastructure.ps1 -Action destroy -Subscription '<id>'

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("init", "plan", "apply", "all", "destroy", "output")]
    [string]$Action,

    [Parameter(Mandatory=$true)]
    [string]$Subscription,

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",

    [Parameter(Mandatory=$false)]
    [string]$TfStateStorageAccount = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/common/DeploymentFunctions.psm1" -Force

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

function New-TerraformVarsFile {
    param(
        [string]$SubscriptionId,
        [string]$Location,
        [string]$Environment,
        [string]$OutputPath = "."
    )

    Write-Title "Generating terraform.tfvars"
    $absolutePath  = (Resolve-Path -Path $OutputPath).Path
    $resourceToken = Get-ResourceToken -SubscriptionId $SubscriptionId

    $content = @"
subscription_id  = "$SubscriptionId"
environment_name = "$Environment"
project_name     = "sre"
resource_token   = "$resourceToken"
location         = "$Location"
"@

    $tfvarsPath = Join-Path $absolutePath "terraform.tfvars"
    Set-Content -Path $tfvarsPath -Value $content -Encoding UTF8 -Force
    Write-Success "terraform.tfvars created at: $tfvarsPath"
    Write-Info "Resource token: $resourceToken"
    return $true
}

function Test-Prerequisites {
    Write-Title "Checking Prerequisites"
    $missingTools = @()

    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        $missingTools += "Terraform"
    } else {
        Write-Success "Terraform installed"
    }

    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        $missingTools += "Azure CLI"
    } else {
        Write-Success "Azure CLI installed"
    }

    try {
        $null = az account show --output json | ConvertFrom-Json
        Write-Success "Azure authentication verified"
    } catch {
        $missingTools += "Azure CLI authentication (run 'az login')"
    }

    if ($missingTools.Count -gt 0) {
        Write-Host "Missing prerequisites:" -ForegroundColor Red
        $missingTools | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        exit 1
    }

    Write-Success "All prerequisites met"
    return $true
}

function Initialize-Terraform {
    param([string]$StorageAccount)
    Write-Title "Initializing Terraform"

    terraform init `
        -backend-config="storage_account_name=$StorageAccount" `
        -reconfigure

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Terraform initialized"
        return $true
    } else {
        Write-Host "Terraform initialization failed" -ForegroundColor Red
        return $false
    }
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

Write-Title "Azure SRE Demo - Infrastructure Deployment"

if (-not (Test-Prerequisites)) { exit 1 }

$subscriptionId = az account show --query id -o tsv 2>$null
$tenantId       = az account show --query tenantId -o tsv 2>$null

$env:ARM_TENANT_ID       = $tenantId
$env:ARM_SUBSCRIPTION_ID = $subscriptionId

if (-not $TfStateStorageAccount) {
    $suffix               = ($subscriptionId -replace '-', '').Substring(0, 8).ToLower()
    $TfStateStorageAccount = "stotfsre$suffix"
}
Write-Info "TF state storage account: $TfStateStorageAccount"

$infraDir = Join-Path $PSScriptRoot "../infra"
Set-Location -Path $infraDir

# --- Destroy ---
if ($Action -eq "destroy") {
    if (-not (Initialize-Terraform -StorageAccount $TfStateStorageAccount)) { exit 1 }
    Write-Title "Destroying Resources"
    Write-Host "WARNING: All Terraform-managed resources will be permanently deleted!" -ForegroundColor Red
    Write-Host ""
    $confirmation = Read-Host "Type 'yes' to confirm"
    if ($confirmation -ne "yes") { Write-Host "Cancelled" -ForegroundColor Yellow; exit 0 }

    terraform plan -destroy -out=tfplan
    if ($LASTEXITCODE -ne 0) { Write-Host "Destruction plan failed" -ForegroundColor Red; exit 1 }
    terraform apply tfplan
    if ($LASTEXITCODE -ne 0) { Write-Host "Terraform destroy failed" -ForegroundColor Red; exit 1 }
    Write-Success "Resources destroyed"
    exit 0
}

# --- Output ---
if ($Action -eq "output") {
    if (-not (Initialize-Terraform -StorageAccount $TfStateStorageAccount)) { exit 1 }
    terraform output -json
    exit 0
}

# --- Generate tfvars ---
New-TerraformVarsFile `
    -SubscriptionId $subscriptionId `
    -Location       $Location `
    -Environment    $Environment `
    -OutputPath     $infraDir

# --- Init ---
if ($Action -in @("init", "all")) {
    if (-not (Initialize-Terraform -StorageAccount $TfStateStorageAccount)) { exit 1 }
    if ($Action -eq "init") { exit 0 }
}

# --- Plan ---
if ($Action -in @("plan", "all")) {
    if ($Action -eq "plan") {
        if (-not (Initialize-Terraform -StorageAccount $TfStateStorageAccount)) { exit 1 }
    }
    Write-Title "Planning Deployment"
    terraform plan -out=tfplan
    if ($LASTEXITCODE -ne 0) { Write-Host "Terraform plan failed" -ForegroundColor Red; exit 1 }
    Write-Success "Plan created"
    if ($Action -eq "plan") { exit 0 }
}

# --- Apply ---
if ($Action -in @("apply", "all")) {
    if ($Action -eq "apply") {
        if (-not (Initialize-Terraform -StorageAccount $TfStateStorageAccount)) { exit 1 }
        terraform plan -out=tfplan
        if ($LASTEXITCODE -ne 0) { Write-Host "Terraform plan failed" -ForegroundColor Red; exit 1 }
    }
    Write-Title "Applying Infrastructure"
    Write-Host "This may take 10-15 minutes..." -ForegroundColor Cyan
    terraform apply tfplan
    if ($LASTEXITCODE -ne 0) { Write-Host "Terraform apply failed" -ForegroundColor Red; exit 1 }
    Write-Success "Infrastructure deployed successfully"
    terraform output
}
