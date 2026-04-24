variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment_name" {
  description = "Environment name"
  type        = string
}

variable "resource_token" {
  description = "Resource token"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "managed_identity_id" {
  description = "Resource ID of the managed identity"
  type        = string
}

variable "app_insights_name" {
  description = "Name of Application Insights"
  type        = string
}

variable "container_registry_name" {
  description = "Name of the Azure Container Registry"
  type        = string
}

variable "container_app_environment_id" {
  description = "Resource ID of the Container App Environment"
  type        = string
}

variable "container_app_api_image" {
  description = "Initial image for the API Container App (placeholder until ACR build)"
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "cosmosdb_endpoint" {
  description = "Cosmos DB account endpoint URL"
  type        = string
}

variable "container_app_loadgen_image" {
  description = "Initial image for the load generator Container Apps Job (placeholder until ACR build)"
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}
