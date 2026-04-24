param (
    # GitHub repo in owner/name format. Defaults to the remote of the current git repo.
    [Parameter(Mandatory=$false)]
    [string]$Repo,

    # Entra app registration display name
    [Parameter(Mandatory=$false)]
    [string]$AppName = "sp-sre-github",

    # Branch that triggers the workflow (federated credential subject)
    [Parameter(Mandatory=$false)]
    [string]$Branch = "main",

    # Azure role to grant the service principal at subscription scope
    [Parameter(Mandatory=$false)]
    [string]$Role = "Contributor"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve repo from git remote if not supplied
# ---------------------------------------------------------------------------
if (-not $Repo) {
    $remote = git remote get-url origin 2>$null
    if ($remote -match 'github\.com[:/](.+?)(?:\.git)?$') {
        $Repo = $Matches[1]
        Write-Host "Auto-detected repo: $Repo" -ForegroundColor Cyan
    } else {
        Write-Error "Could not detect GitHub repo from git remote. Pass -Repo 'owner/name'."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Resolve subscription / tenant from current az login
# ---------------------------------------------------------------------------
Write-Host "`nReading Azure account..." -ForegroundColor Cyan
$account        = az account show | ConvertFrom-Json
$subscriptionId = $account.id
$tenantId       = $account.tenantId
Write-Host "  Subscription : $subscriptionId"
Write-Host "  Tenant       : $tenantId"
Write-Host "  Repo         : $Repo"
Write-Host "  App name     : $AppName"

# ---------------------------------------------------------------------------
# Create (or reuse) app registration
# ---------------------------------------------------------------------------
Write-Host "`nChecking for existing app registration '$AppName'..." -ForegroundColor Cyan
$existingApps = az ad app list --display-name $AppName | ConvertFrom-Json

if ($existingApps.Count -gt 0) {
    $clientId = $existingApps[0].appId
    Write-Host "  Reusing existing app: $clientId" -ForegroundColor Yellow
} else {
    Write-Host "  Creating app registration..." -ForegroundColor Cyan
    $app      = az ad app create --display-name $AppName | ConvertFrom-Json
    $clientId = $app.appId
    Write-Host "  Created: $clientId" -ForegroundColor Green

    # Create service principal
    az ad sp create --id $clientId | Out-Null
    Write-Host "  Service principal created." -ForegroundColor Green

    # Wait briefly for SP propagation
    Start-Sleep -Seconds 10
}

# ---------------------------------------------------------------------------
# Role assignment (idempotent)
# ---------------------------------------------------------------------------
Write-Host "`nAssigning '$Role' role at subscription scope..." -ForegroundColor Cyan
$scope = "/subscriptions/$subscriptionId"

$existingRole = az role assignment list `
    --assignee $clientId `
    --role $Role `
    --scope $scope `
    --query "[0].id" -o tsv 2>$null

if ($existingRole) {
    Write-Host "  Role already assigned." -ForegroundColor Yellow
} else {
    az role assignment create `
        --assignee $clientId `
        --role $Role `
        --scope $scope `
        --output none
    Write-Host "  Role assigned." -ForegroundColor Green
}

# Also grant Storage Blob Data Contributor so Terraform can access state backend
Write-Host "  Granting Storage Blob Data Contributor for Terraform state..." -ForegroundColor Cyan
$existingStorage = az role assignment list `
    --assignee $clientId `
    --role "Storage Blob Data Contributor" `
    --scope $scope `
    --query "[0].id" -o tsv 2>$null

if (-not $existingStorage) {
    az role assignment create `
        --assignee $clientId `
        --role "Storage Blob Data Contributor" `
        --scope $scope `
        --output none
}

# ---------------------------------------------------------------------------
# Federated credential for GitHub Actions
# ---------------------------------------------------------------------------
Write-Host "`nConfiguring federated credential for GitHub Actions..." -ForegroundColor Cyan

$credName    = "github-actions-$($Branch -replace '[^a-zA-Z0-9]','-')"
$credSubject = "repo:${Repo}:ref:refs/heads/${Branch}"

$existingCreds = az ad app federated-credential list --id $clientId | ConvertFrom-Json
$existing = @($existingCreds) | Where-Object { $_ -and ($_ | Get-Member -Name subject -ErrorAction SilentlyContinue) -and $_.subject -eq $credSubject }

if ($existing) {
    Write-Host "  Federated credential already exists." -ForegroundColor Yellow
} else {
    $credBody = @{
        name      = $credName
        issuer    = "https://token.actions.githubusercontent.com"
        subject   = $credSubject
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Depth 5

    # Write JSON to a temp file — avoids PowerShell/az CLI quoting issues
    $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
    $credBody | Out-File -FilePath $tempFile -Encoding utf8

    az ad app federated-credential create `
        --id $clientId `
        --parameters "@$tempFile" `
        --output none

    Remove-Item $tempFile -Force

    Write-Host "  Federated credential created (subject: $credSubject)." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Set GitHub secrets
# ---------------------------------------------------------------------------
Write-Host "`nSetting GitHub repository secrets..." -ForegroundColor Cyan

gh secret set AZURE_CLIENT_ID       --body $clientId       --repo $Repo
gh secret set AZURE_TENANT_ID       --body $tenantId       --repo $Repo
gh secret set AZURE_SUBSCRIPTION_ID --body $subscriptionId --repo $Repo

# Resolve the service principal object ID (needed by Terraform for data-plane
# role assignments: KV Secrets Officer, AI Project Management, AI User, etc.)
$spObjectId = az ad sp show --id $clientId --query id -o tsv 2>$null
if ($spObjectId) {
    gh secret set AZURE_SP_OBJECT_ID --body $spObjectId --repo $Repo
    Write-Host "  AZURE_SP_OBJECT_ID  = $spObjectId" -ForegroundColor Cyan
} else {
    Write-Host "  WARNING: Could not resolve SP object ID - set AZURE_SP_OBJECT_ID manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Done!  Secrets written to $Repo"                            -ForegroundColor Green
Write-Host ""                                                              -ForegroundColor Green
Write-Host "  AZURE_CLIENT_ID       = $clientId"                          -ForegroundColor Green
Write-Host "  AZURE_TENANT_ID       = $tenantId"                          -ForegroundColor Green
Write-Host "  AZURE_SUBSCRIPTION_ID = $subscriptionId"                    -ForegroundColor Green
Write-Host "  AZURE_SP_OBJECT_ID    = $spObjectId"                        -ForegroundColor Green
Write-Host ""                                                              -ForegroundColor Green
Write-Host "  Push to main to trigger the first deploy."                  -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
