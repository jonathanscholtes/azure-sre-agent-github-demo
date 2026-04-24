terraform {
  # Partial backend configuration — storage account name is supplied at
  # 'terraform init' time via -backend-config so the same code works locally
  # and in GitHub Actions without committing secrets.
  #
  # Bootstrap the state backend once before first deploy:
  #   az group create -n rg-tfstate-sre -l eastus2
  #   az storage account create -n <name> -g rg-tfstate-sre --sku Standard_LRS
  #   az storage container create -n tfstate --account-name <name>
  #
  # Then init with:
  #   terraform init -backend-config="storage_account_name=<name>"
  backend "azurerm" {
    resource_group_name = "rg-tfstate-sre"
    container_name      = "tfstate"
    key                 = "sre-demo.tfstate"
    use_azuread_auth    = true
    # storage_account_name supplied via -backend-config at init time
  }
}

# Generate unique resource token if not provided
resource "random_string" "resource_token" {
  length  = 8
  special = false
  upper   = false
  lower   = true
  numeric = true
}

locals {
  resource_token      = var.resource_token != "" ? var.resource_token : random_string.resource_token.result
  resource_group_name = "rg-${var.project_name}-${var.environment_name}-${var.location}-${local.resource_token}"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
}

# Security Module (Key Vault, Managed Identity)
module "security" {
  source = "./modules/security"

  key_vault_name        = "kv${var.project_name}${local.resource_token}"
  managed_identity_name = "id-${var.project_name}-${var.environment_name}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
}

# Monitoring Module (Log Analytics, Application Insights)
module "monitor" {
  source = "./modules/monitor"

  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  log_analytics_name        = "log-${var.project_name}-${var.environment_name}-${local.resource_token}"
  application_insights_name = "appi-${var.project_name}-${var.environment_name}-${local.resource_token}"

  depends_on = [module.security]
}

# Data Module (Cosmos DB — orders and customers)
module "data" {
  source = "./modules/data"

  project_name          = var.project_name
  environment_name      = var.environment_name
  resource_token        = local.resource_token
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  identity_principal_id = module.security.managed_identity_principal_id

  depends_on = [module.security]
}

# Platform Module (ACR + Container App Environment)
module "platform" {
  source = "./modules/platform"

  project_name               = var.project_name
  environment_name           = var.environment_name
  resource_token             = local.resource_token
  location                   = var.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = module.monitor.log_analytics_workspace_id
}

# SRE Agent Module
module "sre_agent" {
  count  = var.enable_sre_agent ? 1 : 0
  source = "./modules/sre-agent"

  agent_name                             = var.sre_agent_name
  location                               = var.location
  resource_group_name                    = azurerm_resource_group.main.name
  subscription_id                        = var.subscription_id
  resource_token                         = local.resource_token
  access_level                           = var.sre_agent_access_level
  # Always include the deployment resource group so the agent can observe the
  # Container App, Cosmos DB, and Application Insights that live there.
  # Additional resource groups can be appended via sre_agent_target_resource_groups.
  target_resource_groups = concat(
    [{ name = azurerm_resource_group.main.name, subscription_id = var.subscription_id }],
    var.sre_agent_target_resource_groups
  )
  application_insights_app_id            = module.monitor.application_insights_app_id
  application_insights_connection_string = module.monitor.application_insights_connection_string

  depends_on = [module.monitor]
}

# Apps Module (Backend API Container App)
module "apps" {
  source = "./modules/apps"

  project_name                 = var.project_name
  environment_name             = var.environment_name
  resource_token               = local.resource_token
  location                     = var.location
  resource_group_name          = azurerm_resource_group.main.name
  managed_identity_id          = module.security.managed_identity_id
  app_insights_name            = module.monitor.application_insights_name
  container_registry_name      = module.platform.container_registry_name
  container_app_environment_id = module.platform.container_app_environment_id
  cosmosdb_endpoint            = module.data.cosmosdb_endpoint

  depends_on = [
    module.platform,
    module.monitor,
    module.security,
    module.data,
  ]
}
