# Infrastructure – Terraform

Terraform configuration for the Azure SRE Agent demo. Deploys all resources in a single `terraform apply`.

## Modules

```
infra/
├── main.tf              # Root config, module wiring, resource group
├── variables.tf         # Input variables
├── outputs.tf           # Outputs (17 values)
├── providers.tf         # azurerm ~> 4.0, azapi ~> 2.0, random ~> 3.6
├── terraform.tfvars.example
└── modules/
    ├── security/        # User-assigned Managed Identity + Key Vault
    ├── monitor/         # Log Analytics Workspace + Application Insights
    ├── platform/        # Azure Container Registry + Container App Environment
    ├── data/            # Cosmos DB account (orders + customers containers)
    ├── apps/            # Backend Container App + Load Generator Job (5-min cron)
    └── sre-agent/       # Azure SRE Agent (Microsoft.App/agents preview via azapi)
```

## Prerequisites

- Terraform >= 1.5
- Azure CLI (authenticated via `az login`)
- Contributor + User Access Administrator on the subscription

## State Backend

Remote state is stored in Azure Blob Storage. Bootstrap the backend once before the first deploy (the `deploy.ps1` script does this automatically):

```powershell
az group create -n rg-tfstate-sre -l eastus2
az storage account create -n <unique-name> -g rg-tfstate-sre --sku Standard_LRS
az storage container create -n tfstate --account-name <unique-name>
```

Then initialize with the storage account name supplied at init time:

```powershell
cd infra
terraform init -backend-config="storage_account_name=<unique-name>"
```

The remaining backend config (`resource_group_name`, `container_name`, `key`) is hardcoded in `main.tf`.

## Configuration

Copy the example vars file and fill in your values:

```powershell
Copy-Item infra/terraform.tfvars.example infra/terraform.tfvars
```

| Variable | Required | Description |
|----------|----------|-------------|
| `subscription_id` | Yes | Azure subscription ID |
| `environment_name` | Yes | e.g. `dev`, `prod` — used in resource naming |
| `project_name` | Yes | Short identifier used in resource naming |
| `resource_token` | No | Unique suffix (auto-generated if omitted) |
| `location` | Yes | Azure region — SRE Agent requires `eastus2`, `swedencentral`, `uksouth`, or `australiaeast` |
| `enable_sre_agent` | No | Deploy the SRE Agent resource (default: `false`) |
| `sre_agent_name` | No | Name of the SRE Agent resource (default: `sre-agent`) |
| `sre_agent_access_level` | No | `High` or `Low` — controls RBAC granted to the agent (default: `High`) |
| `sre_agent_target_resource_groups` | No | Additional resource groups for the agent to monitor |

## Deployment

The recommended path is `deploy.ps1` from the project root, which handles bootstrapping, variable generation, and container builds in one pass. For manual Terraform runs:

```powershell
cd infra

terraform init -backend-config="storage_account_name=<name>"

terraform plan \
  -var="subscription_id=<sub>" \
  -var="environment_name=dev" \
  -var="project_name=sre" \
  -var="location=eastus2" \
  -out=tfplan

terraform apply tfplan
```

To enable the SRE Agent, add `-var="enable_sre_agent=true"` to the plan command, or set `enable_sre_agent = true` in `terraform.tfvars`.

## Outputs

| Output | Description |
|--------|-------------|
| `resource_group_name` | Resource group containing all resources |
| `managed_identity_name/id/client_id/principal_id` | Managed identity used by the Container App |
| `container_registry_name` | ACR where `sre-api` and `sre-loadgen` images are pushed |
| `container_app_environment_name` | Container App Environment |
| `log_analytics_workspace_name` | Log Analytics workspace |
| `application_insights_name/id` | Application Insights instance |
| `backend_container_app_name/url` | FastAPI order-management API |
| `load_generator_job_name` | 5-min cron job that generates synthetic traffic |
| `cosmosdb_endpoint` | Cosmos DB account endpoint |
| `sre_agent_name` | SRE Agent name (empty when disabled) |
| `sre_agent_portal_url` | Portal deep-link to the SRE Agent (empty when disabled) |
| `sre_agent_identity_id` | SRE Agent managed identity resource ID |

```powershell
# View all outputs
terraform output

# View a specific output
terraform output backend_container_app_url
```

## Destroy

```powershell
terraform destroy
```

This removes all resources in the resource group. The Terraform state backend storage account is in a separate resource group (`rg-tfstate-sre`) and is not destroyed.
