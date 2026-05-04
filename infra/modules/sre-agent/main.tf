terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  # Roles assigned to the SRE agent identity on each target resource group.
  # The deployment resource group is always included in var.target_resource_groups
  # by the root module, so these roles cover it as well.
  target_rg_roles = var.access_level == "High" ? [
    "Log Analytics Reader",
    "Reader",
    "Contributor",
  ] : ["Log Analytics Reader", "Reader"]

  # Flattened map of (target_rg, role) pairs for for_each
  target_rg_role_assignments = {
    for pair in flatten([
      for rg in var.target_resource_groups : [
        for role in local.target_rg_roles : {
          key  = "${rg.subscription_id}/${rg.name}/${role}"
          sub  = rg.subscription_id
          name = rg.name
          role = role
        }
      ]
    ]) : pair.key => pair
  }
}

# Dedicated managed identity for the SRE agent
resource "azurerm_user_assigned_identity" "sre_agent" {
  name                = "id-sre-agent-${var.resource_token}"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Role assignments on each target resource group (includes the deployment RG)
resource "azurerm_role_assignment" "target_rg" {
  for_each = local.target_rg_role_assignments

  scope                = "/subscriptions/${each.value.sub}/resourceGroups/${each.value.name}"
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.sre_agent.principal_id
  principal_type       = "ServicePrincipal"
}

# SRE Agent — requires azapi because Microsoft.App/agents is a preview resource type
# not yet available in the azurerm provider
resource "azapi_resource" "sre_agent" {
  type      = "Microsoft.App/agents@2025-05-01-preview"
  name      = var.agent_name
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  location  = var.location

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.sre_agent.id]
  }

  body = {
    properties = {
      knowledgeGraphConfiguration = {
        identity = azurerm_user_assigned_identity.sre_agent.id
        managedResources = [
          for rg in var.target_resource_groups :
          "/subscriptions/${rg.subscription_id}/resourceGroups/${rg.name}"
        ]
      }
      actionConfiguration = {
        accessLevel = var.access_level
        identity    = azurerm_user_assigned_identity.sre_agent.id
        mode        = "Review"
      }
      logConfiguration = {
        applicationInsightsConfiguration = {
          appId            = var.application_insights_app_id
          connectionString = var.application_insights_connection_string
        }
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_role_assignment.target_rg,
  ]
}

# Grant the deployer SRE Agent Administrator on the agent resource so they can
# manage it via the portal and configure workflows
resource "azurerm_role_assignment" "sre_agent_admin" {
  scope              = azapi_resource.sre_agent.id
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/e79298df-d852-4c6d-84f9-5d13249d1e55"
  principal_id       = data.azurerm_client_config.current.object_id
  principal_type     = "User"
}
