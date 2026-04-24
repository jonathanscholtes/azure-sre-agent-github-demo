variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "environment_name" {
  description = "Deployment environment (e.g. 'dev', 'lab', 'prod'); used in resource naming"
  type        = string
  validation {
    condition     = length(var.environment_name) >= 1 && length(var.environment_name) <= 64
    error_message = "Environment name must be between 1 and 64 characters."
  }
}

variable "project_name" {
  description = "Short project identifier used in resource naming"
  type        = string
  validation {
    condition     = length(var.project_name) >= 1 && length(var.project_name) <= 64
    error_message = "Project name must be between 1 and 64 characters."
  }
}

variable "resource_token" {
  description = "Unique token appended to resource names to avoid collisions (auto-generated if empty)"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region where all resources will be deployed (e.g. 'eastus2')"
  type        = string
  validation {
    condition     = length(var.location) >= 1
    error_message = "Location must not be empty."
  }
}

# ── SRE Agent ────────────────────────────────────────────────────────────────

variable "enable_sre_agent" {
  description = "Deploy the Azure SRE Agent. Requires a location supported by the preview: eastus2, swedencentral, uksouth, australiaeast."
  type        = bool
  default     = false
}

variable "sre_agent_name" {
  description = "Name of the SRE Agent resource (must be unique within the resource group)"
  type        = string
  default     = "sre-agent"
}

variable "sre_agent_access_level" {
  description = "Access level granted to the SRE agent on managed resource groups (High or Low)"
  type        = string
  default     = "High"
  validation {
    condition     = contains(["High", "Low"], var.sre_agent_access_level)
    error_message = "sre_agent_access_level must be High or Low."
  }
}

variable "sre_agent_target_resource_groups" {
  description = "Additional resource groups the SRE agent should monitor (defaults to the deployment resource group)"
  type = list(object({
    name            = string
    subscription_id = string
  }))
  default = []
}
