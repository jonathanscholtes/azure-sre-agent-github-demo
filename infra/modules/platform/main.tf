locals {
  container_registry_name       = "cr${var.project_name}${var.resource_token}"
  container_app_environment_name = "cae-${var.project_name}-${var.environment_name}-${var.resource_token}"
}

# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = local.container_registry_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  admin_enabled       = false
}

# Container App Environment
resource "azurerm_container_app_environment" "main" {
  name                       = local.container_app_environment_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_workspace_id
}
