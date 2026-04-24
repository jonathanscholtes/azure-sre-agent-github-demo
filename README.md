# Azure SRE Agent – Closed-Loop Reliability Demo

A hands-on demo of a **closed-loop reliability workflow** where an intentional application failure is automatically detected, investigated, and fixed — with a human approving the final merge.

```
Bug injected → Application Insights detects errors
             → Azure SRE Agent investigates & files ADO bug
             → GitHub Copilot coding agent opens fix PR
             → Human reviews & merges
             → CI/CD deploys clean code
```

---

## What This Demo Shows

| Step | Tool | Action |
|------|------|--------|
| 1 | Container Apps + Load Generator | Synthetic traffic hits a deliberately broken API |
| 2 | Application Insights | Exception rate spike detected |
| 3 | Azure SRE Agent | Root-cause analysis; structured bug filed in ADO |
| 4 | GitHub Copilot Coding Agent | Reads ADO bug, opens a fix PR |
| 5 | Human reviewer | Reviews and merges the PR |
| 6 | GitHub Actions | CI/CD deploys the fix; errors stop |

---

## Architecture

```
┌─────────────────────────┐
│  Azure Container Apps   │  ← FastAPI order-management API
│  + Load Generator Job   │  ← 5-min cron, synthetic traffic
└────────────┬────────────┘
             │ exceptions
             ▼
┌─────────────────────────┐
│   Application Insights  │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│   Azure SRE Agent       │  ← investigates, deduplicates
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│   Azure DevOps Boards   │  ← structured bug with telemetry link
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  GitHub Copilot Agent   │  ← reads bug, creates branch + PR
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│  Human Review + Merge   │  ← the human gate
└─────────────────────────┘
             │
             ▼ GitHub Actions deploy.yml
┌─────────────────────────┐
│  Clean API deployed     │
└─────────────────────────┘
```

**Infrastructure** (all Terraform):
- Azure Container Registry
- Azure Container Apps Environment + App + Job
- Cosmos DB (orders + customers containers)
- Log Analytics Workspace + Application Insights
- Key Vault + User-Assigned Managed Identity
- Azure SRE Agent (`Microsoft.App/agents` preview)

---

## Prerequisites

| Tool | Version |
|------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.5 |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | latest |
| [PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) | >= 7 |
| [GitHub CLI](https://cli.github.com/) | latest (for OIDC setup) |
| Azure subscription | Contributor + User Access Administrator |
| Azure DevOps organization | For SRE Agent bug filing |
| GitHub Copilot Enterprise | For coding agent PR creation |

> **SRE Agent region constraint**: the agent resource is only available in `eastus2`, `swedencentral`, `uksouth`, and `australiaeast`.

---

## Quick Start

### 1. Clone and initialize

```powershell
git clone https://github.com/<your-org>/Azure-SRE-GitHub-Copilot-Demo
cd Azure-SRE-GitHub-Copilot-Demo
az login
```

### 2. Deploy infrastructure and containers

```powershell
.\deploy.ps1
```

The script runs four phases automatically:

| Phase | What happens |
|-------|-------------|
| 0 – Bootstrap | Creates Azure Storage for Terraform remote state |
| 1 – Infrastructure | `terraform init / plan / apply` (all 6 modules) |
| 2 – Containers | Builds and pushes `sre-api` and `sre-loadgen` images to ACR |
| 3 – Demo data | Seeds Cosmos DB with sample customers and orders |

Subsequent runs skip the bootstrap:

```powershell
.\deploy.ps1 -SkipBootstrap
```

To tear everything down:

```powershell
.\deploy.ps1 -Destroy
```

### 3. Set up GitHub Actions CI/CD (optional)

Wire up OIDC federated credentials and set repository secrets automatically:

```powershell
.\deploy.ps1 -SetupGitHub
# or run standalone:
.\scripts\New-GitHubOidc.ps1
```

This creates an Entra app registration, grants it Contributor on the subscription, and sets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, and `AZURE_SP_OBJECT_ID` as GitHub secrets.

You also need to set one additional secret manually after bootstrap:

```
TF_STATE_STORAGE_ACCOUNT = <name printed by deploy.ps1 phase 0>
```

### 4. Connect SRE Agent to Azure DevOps (portal)

After the first `terraform apply`:

1. Open the SRE Agent resource in the Azure portal
2. Go to **Workflows** → add a new workflow
3. Connect your ADO organization, project, and board
4. The agent will now file bugs automatically when it detects anomalies

### 5. Connect GitHub Copilot to ADO (portal)

1. Install the **Azure Boards** GitHub App on this repository
2. In ADO, install the **GitHub Copilot for Azure DevOps** extension
3. Configure it to assign new bugs to the Copilot coding agent

---

## Running the Demo

### Start (inject bug + generate errors)

```powershell
.\tools\Start-SreDemo.ps1
```

This injects one of two bugs into the running API, rebuilds and redeploys the image, waits for the new revision to become healthy, then fires a burst of 20 orders to flood Application Insights with errors. It prints direct portal deep-links for each presenter step.

```powershell
# Inject a specific bug type
.\tools\Start-SreDemo.ps1 -Bug KeyError -LoadCount 30
```

**Bug types:**

| Bug | Symptom |
|-----|---------|
| `KeyError` | `unit_price` key renamed to `price` — invoice calculation crashes |
| `AttributeError` | `req.lineItems` accessed instead of `req.line_items` |
| `Random` | One of the above, chosen at random (default) |

### Presenter flow

1. **Application Insights → Failures blade** — show error rate spike, exception type, stack trace
2. **Azure SRE Agent** — show the agent investigating and filing an ADO bug
3. **Azure DevOps Boards** — show the structured bug with telemetry links
4. **GitHub** — show Copilot opening a fix PR
5. **Merge the PR** — CI/CD deploys the fix; errors stop

### Reset after the demo

```powershell
.\tools\Invoke-ChaosBug.ps1 -Revert `
    -ContainerRegistryName <acr> `
    -ResourceGroupName     <rg> `
    -BackendAppName        <app>
```

Or get the values from Terraform and pass them automatically — `Start-SreDemo.ps1` prints the exact reset command at the end of its output.

---

## Project Structure

```
.
├── .github/workflows/
│   └── deploy.yml          # CI/CD: Terraform + ACR build + health check
├── apps/
│   ├── api/                # FastAPI order-management backend
│   │   ├── main.py
│   │   ├── Dockerfile
│   │   └── app/
│   │       ├── routes/     # health, customers, orders, demo
│   │       └── stores/     # Cosmos DB stores with in-memory fallback
│   └── loadgen/            # Synthetic load generator (Container Apps Job)
├── infra/
│   ├── main.tf / variables.tf / outputs.tf / providers.tf
│   └── modules/
│       ├── security/       # Managed Identity + Key Vault
│       ├── monitor/        # Log Analytics + Application Insights
│       ├── platform/       # ACR + Container App Environment
│       ├── data/           # Cosmos DB
│       ├── apps/           # Container App + Load Generator Job
│       └── sre-agent/      # Azure SRE Agent (azapi preview resource)
├── scripts/
│   ├── Deploy-Infrastructure.ps1
│   ├── Deploy-Containers.ps1
│   ├── New-GitHubOidc.ps1
│   └── common/DeploymentFunctions.psm1
├── tools/
│   ├── Start-SreDemo.ps1   # Demo orchestrator + presenter guide
│   └── Invoke-ChaosBug.ps1 # Inject / revert intentional bugs
├── deploy.ps1              # Main deployment orchestrator
└── project.md              # Architecture notes
```

---

## API Reference

The FastAPI backend exposes a Swagger UI at `<api-url>/docs`.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (includes Cosmos DB connectivity) |
| GET | `/api/customers` | List customers |
| GET | `/api/orders` | List orders |
| POST | `/api/orders` | Create an order |
| POST | `/api/orders/{id}/process` | Process an order (invoice generation — this is where the bugs live) |
| POST | `/api/demo/seed` | Seed sample data |
| POST | `/api/demo/simulate-load` | Generate synthetic load burst |

---

## Terraform Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `subscription_id` | Yes | Azure subscription ID |
| `environment_name` | Yes | e.g. `dev`, `prod` |
| `project_name` | Yes | Used in resource naming |
| `resource_token` | Yes | Unique suffix (e.g. commit hash) |
| `location` | Yes | Azure region (SRE Agent constraint applies) |

Copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars` and fill in your values. The `deploy.ps1` script generates this file automatically.
