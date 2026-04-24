variable "agent_name" {
  description = "Name of the SRE Agent resource"
  type        = string
}

variable "location" {
  description = "Azure region — must be one of: eastus2, swedencentral, uksouth, australiaeast"
  type        = string
  validation {
    condition     = contains(["eastus2", "swedencentral", "uksouth", "australiaeast"], var.location)
    error_message = "SRE Agent is only available in eastus2, swedencentral, uksouth, and australiaeast."
  }
}

variable "resource_group_name" {
  description = "Resource group where the SRE Agent and its supporting resources are deployed"
  type        = string
}

variable "subscription_id" {
  description = "Subscription ID where the SRE Agent is deployed"
  type        = string
}

variable "resource_token" {
  description = "Unique suffix used to avoid naming collisions on the managed identity"
  type        = string
}

variable "access_level" {
  description = "Access level granted to the SRE agent on managed resource groups"
  type        = string
  default     = "High"
  validation {
    condition     = contains(["High", "Low"], var.access_level)
    error_message = "access_level must be High or Low."
  }
}

variable "target_resource_groups" {
  description = "Resource groups the SRE agent will monitor and manage"
  type = list(object({
    name            = string
    subscription_id = string
  }))
  default = []
}

variable "application_insights_app_id" {
  description = "AppId (GUID) of the Application Insights instance for SRE agent telemetry"
  type        = string
}

variable "application_insights_connection_string" {
  description = "Connection string of the Application Insights instance"
  type        = string
  sensitive   = true
}
