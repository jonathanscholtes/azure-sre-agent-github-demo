# Deployment Guide

Step-by-step instructions for deploying the Azure SRE Agent closed-loop demo.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5 | |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | latest | |
| [PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) | >= 7 | |
| [GitHub CLI](https://cli.github.com/) | latest | Required for OIDC setup |
| Azure subscription | | Contributor + User Access Administrator |
| Azure DevOps organization | | Required for SRE Agent WorkItem filing |
| GitHub Copilot Enterprise | | Required for coding agent PR creation |

> **Region constraint**: The SRE Agent resource (`Microsoft.App/agents`) is currently available only in `eastus2`, `swedencentral` and `australiaeast`. Set `location` in `terraform.tfvars` accordingly.

---

## Step 1 — Clone and authenticate

```powershell
git clone https://github.com/jonathanscholtes/azure-sre-agent-github-demo
cd azure-sre-agent-github-demo
az login
```

---

## Step 2 — Deploy infrastructure and containers

```powershell
.\deploy.ps1 -Subscription "<subscription-name-or-id>"
```

The script runs four phases automatically:

| Phase | What happens |
|-------|-------------|
| 0 – Bootstrap | Creates Azure Storage for Terraform remote state |
| 1 – Infrastructure | `terraform init / plan / apply` across all modules |
| 2 – Containers | Builds and pushes `sre-api` and `sre-loadgen` to ACR |
| 3 – Demo data | Seeds Cosmos DB with sample customers and orders |

Subsequent runs skip the bootstrap step:

```powershell
.\deploy.ps1 -SkipBootstrap
```

---

## Step 3 — Set up GitHub Actions CI/CD

Wire up OIDC federated credentials and GitHub repository secrets:

```powershell
.\deploy.ps1 -SetupGitHub
# or standalone:
.\scripts\New-GitHubOidc.ps1
```

This creates an Entra app registration, grants it Contributor on the subscription, and sets the following GitHub secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_SP_OBJECT_ID`

Set one additional secret manually after the bootstrap phase completes:

```
TF_STATE_STORAGE_ACCOUNT = <storage account name printed by deploy.ps1 phase 0>
```

---

## Step 4 — Connect SRE Agent to Azure DevOps (Azure portal)

After `terraform apply` completes:

1. Open the SRE Agent resource in the Azure portal
2. Go to **Workflows** → add a new workflow
3. Set the **trigger**: Log Analytics workspace connected to Application Insights — the agent queries exception rates and failure metrics
4. Set the **destination**: your ADO organization, project, and board; work item type **Issue**
5. Save — the agent will now create an ADO WorkItem automatically when an anomaly is detected, including the exception type, stack trace, and telemetry deep-links

---

## Step 5 — Connect SRE Agent to GitHub Issues (Azure portal)

In the same or a parallel workflow in the SRE Agent portal:

1. Add a **GitHub** destination
2. Authenticate and select this repository
3. Set the assignee to **GitHub Copilot** (the coding agent)
4. Save — the agent will now open a GitHub Issue with diagnostic context and assign Copilot to resolve it

> Both the ADO WorkItem and the GitHub Issue come from the same SRE Agent investigation. ADO tracks the incident operationally; the GitHub Issue is the work item Copilot acts on.

---

## Step 6 — Enable branch protection on `main`

This enforces the human gate — Copilot's fix PR cannot merge without a review.

1. Go to **Settings → Branches → Add branch ruleset**
2. Target: `main`
3. Enable:
   - **Require a pull request before merging** (1 required approval)
   - **Require status checks to pass** → add `Validate` (from `validate.yml`)
   - **Block force pushes**

---

## Terraform Variables

Copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars` and fill in your values. `deploy.ps1` generates this file automatically during deployment.

| Variable | Required | Description |
|----------|----------|-------------|
| `subscription_id` | Yes | Azure subscription ID |
| `environment_name` | Yes | Short environment label, e.g. `dev` |
| `project_name` | Yes | Used in resource naming |
| `location` | Yes | Azure region — see region constraint above |
| `resource_token` | No | Unique suffix; auto-generated if empty |
| `enable_sre_agent` | No | Defaults to `true` |
| `sre_agent_access_level` | No | `High` (Reader + Contributor) or `Low` (Reader only) |

---

## Clean Up

```powershell
.\deploy.ps1 -Subscription "<subscription-name-or-id>" -Destroy
```

> The Terraform remote state storage account is in a separate resource group (`rg-tfstate-sre`) and is **not** deleted by the above command. Delete it manually when no longer needed.
