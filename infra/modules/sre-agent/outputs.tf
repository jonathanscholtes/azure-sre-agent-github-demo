output "agent_name" {
  description = "Name of the SRE Agent resource"
  value       = azapi_resource.sre_agent.name
}

output "agent_id" {
  description = "Resource ID of the SRE Agent"
  value       = azapi_resource.sre_agent.id
}

output "agent_portal_url" {
  description = "Azure portal deep-link to the SRE Agent"
  value       = "https://ms.portal.azure.com/#view/Microsoft_Azure_PaasServerless/AgentFrameBlade.ReactView/id/${replace(azapi_resource.sre_agent.id, "/", "%2F")}"
}

output "identity_id" {
  description = "Resource ID of the SRE agent's user-assigned managed identity"
  value       = azurerm_user_assigned_identity.sre_agent.id
}

output "identity_principal_id" {
  description = "Principal ID of the SRE agent's managed identity"
  value       = azurerm_user_assigned_identity.sre_agent.principal_id
}
