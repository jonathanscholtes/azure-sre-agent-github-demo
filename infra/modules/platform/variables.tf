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

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace"
  type        = string
}
