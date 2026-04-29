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
| Azure DevOps organization | | Required for SRE Agent work item filing |
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
.\deploy.ps1 -Subscription "<subscription-name-or-id>" -SkipBootstrap
```

---

## Step 3 — Set up GitHub Actions CI/CD

Wire up OIDC federated credentials and GitHub repository secrets:

```powershell
.\deploy.ps1 -Subscription "<subscription-name-or-id>" -SetupGitHub
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

## Step 4 — Configure incident platform and response plan (Azure portal)

In the SRE Agent resource, configure inbound incident routing from Azure Monitor:

1. Open the SRE Agent resource in the Azure portal
2. Go to **Builder → Incident Platform**
3. Select **Azure Monitor** as the incident platform and complete the connection
4. Go to **Builder → Incident response plans** and create (or customize) a plan for this demo
5. Set plan filters (for example severity/service/title) and set run mode to **Autonomous** for this demo
6. Save and enable the plan

Azure SRE leverages **Memories**, for resolution, tracking and routing intent (for example: create an Azure DevOps **Issue** and route code-fix work to **GitHub Copilot**). This helps keep behavior consistent across incidents. 

> You can use the built-in SRE Agent chat to refine investigation and routing behavior **Memories**, then update the response plan configuration based on those results.

When incidents match the enabled response plan filters, the agent runs automatically from that incident context.

> References:
> - [Incident platforms](https://learn.microsoft.com/en-us/azure/sre-agent/incident-platforms)
> - [Automate incident response](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response)
> - [Incident response plans](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response-plans)
> - [Workflow automation](https://learn.microsoft.com/en-us/azure/sre-agent/workflow-automation)
> - [User memories](https://learn.microsoft.com/en-us/azure/sre-agent/memory#user-memories)

---

## Step 5 — Add Azure DevOps as an automated destination

After `terraform apply` completes:

1. Open the SRE Agent resource in the Azure portal
2. Go to **Builder → Connectors** and create an **Azure DevOps connector** (org, project, board, auth)
3. Select the target Azure DevOps project/repository context for this demo
4. Save — when incidents match the enabled response plan, the agent automatically creates/updates Azure DevOps work items using this connector

---

## Step 6 — Add GitHub Issues as an automated destination

In the same or a parallel workflow in the SRE Agent portal:

1. Go to **Builder → Connectors** and create a **GitHub connector** for this repository
2. Select this repository in the connector configuration
3. Save — for each matching incident, the agent automatically opens a GitHub Issue with diagnostic context and assigns GitHub Copilot to complete the fix



> Connector reference: [Azure SRE Agent connectors documentation](https://learn.microsoft.com/en-us/azure/sre-agent/connectors)

> Both the Azure DevOps work item and the GitHub Issue come from the same SRE Agent investigation. Azure DevOps tracks the incident operationally; the GitHub Issue is the work item Copilot acts on.



---

## Step 7 — Enable branch protection on `main`

This enforces the human gate — Copilot's fix PR cannot merge without a review.

1. Go to **Settings → Branches → Add branch ruleset**
2. Target: `main`
3. Enable:
   - **Require a pull request before merging** (1 required approval)
   - **Require status checks to pass** → add the check run from `.github/workflows/validate.yml` (typically `Lint`)
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
| `enable_sre_agent` | No | Deploy the SRE Agent resource (default: `false`) |
| `sre_agent_name` | No | Name of the SRE Agent resource (default: `sre-agent`) |
| `sre_agent_access_level` | No | `High` (Reader + Contributor) or `Low` (Reader only; default: `High`) |
| `sre_agent_target_resource_groups` | No | Additional resource groups for the agent to monitor |

---

## Clean Up

```powershell
.\deploy.ps1 -Subscription "<subscription-name-or-id>" -Destroy
```

> The Terraform remote state storage account is in a separate resource group (`rg-tfstate-sre`) and is **not** deleted by the above command. Delete it manually when no longer needed.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `deploy.ps1` fails before Terraform | Not authenticated to the correct subscription | Run `az login`, then rerun with `-Subscription` |
| GitHub OIDC setup fails on `gh secret set` | GitHub CLI is not authenticated | Run `gh auth login` and retry Step 3 |
| SRE Agent does not create incidents from alerts | Azure Monitor incident platform or response plan is not enabled | Recheck Step 4 and confirm the response plan is turned on |
| SRE Agent does not create work items/issues | Azure DevOps/GitHub connector project or repository mapping is not configured correctly | Recheck Steps 5 and 6 and verify connector scope |
| Branch rule blocks merge unexpectedly | Required check name mismatch | Use the check run generated by `.github/workflows/validate.yml` |
