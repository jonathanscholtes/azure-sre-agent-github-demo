output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "managed_identity_name" {
  description = "Name of the managed identity"
  value       = module.security.managed_identity_name
}

output "managed_identity_id" {
  description = "Resource ID of the managed identity"
  value       = module.security.managed_identity_id
}

output "managed_identity_client_id" {
  description = "Client ID of the managed identity"
  value       = module.security.managed_identity_client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the managed identity"
  value       = module.security.managed_identity_principal_id
}

output "container_registry_name" {
  description = "Name of the Azure Container Registry"
  value       = module.platform.container_registry_name
}

output "container_app_environment_name" {
  description = "Name of the Container App Environment"
  value       = module.platform.container_app_environment_name
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = module.monitor.log_analytics_workspace_name
}

output "application_insights_name" {
  description = "Name of the Application Insights instance"
  value       = module.monitor.application_insights_name
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance (used to build portal deep-links)"
  value       = module.monitor.application_insights_id
}

output "backend_container_app_url" {
  description = "URL of the backend Order Management API"
  value       = module.apps.backend_container_app_url
}

output "backend_container_app_name" {
  description = "Name of the backend API Container App"
  value       = module.apps.backend_container_app_name
}

output "cosmosdb_endpoint" {
  description = "Cosmos DB account endpoint for local development and scripting"
  value       = module.data.cosmosdb_endpoint
}

output "load_generator_job_name" {
  description = "Name of the synthetic load generator Container Apps Job"
  value       = module.apps.load_generator_job_name
}

output "sre_agent_name" {
  description = "Name of the SRE Agent (empty when enable_sre_agent = false)"
  value       = var.enable_sre_agent ? module.sre_agent[0].agent_name : ""
}

output "sre_agent_portal_url" {
  description = "Azure portal deep-link to the SRE Agent (empty when enable_sre_agent = false)"
  value       = var.enable_sre_agent ? module.sre_agent[0].agent_portal_url : ""
}

output "sre_agent_identity_id" {
  description = "Resource ID of the SRE agent's managed identity (empty when enable_sre_agent = false)"
  value       = var.enable_sre_agent ? module.sre_agent[0].identity_id : ""
}
