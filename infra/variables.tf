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
  description = "Deploy the Azure SRE Agent. Requires a location supported by the preview: eastus2, swedencentral, australiaeast."
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

# ── Alerting ────────────────────────────────────────────────────────────────

variable "enable_alerts" {
  description = "Provision the action group and alert rules in the monitor module."
  type        = bool
  default     = true
}

variable "alert_email_receivers" {
  description = "Email receivers attached to the action group."
  type = list(object({
    name          = string
    email_address = string
  }))
  default = []
}

variable "alert_webhook_receivers" {
  description = "Webhook receivers attached to the action group (PagerDuty, ServiceNow, Teams connector, etc.)."
  type = list(object({
    name        = string
    service_uri = string
  }))
  default = []
}

variable "failed_requests_threshold" {
  description = "Number of failed requests over a 5-minute window that fires the failure-rate alert. Default 0 fits the demo's once-per-5-min load generator (any failure fires)."
  type        = number
  default     = 0
}

variable "response_time_threshold_ms" {
  description = "Average request duration (ms) over a 5-minute window that fires the response-time alert."
  type        = number
  default     = 2000
}

variable "exception_spike_threshold" {
  description = "Exception count over a 5-minute window per type that fires the exception-spike alert. Default 0 fits the demo's once-per-5-min load generator."
  type        = number
  default     = 0
}
