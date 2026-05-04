variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "log_analytics_name" {
  description = "Name of the Log Analytics workspace"
  type        = string
}

variable "application_insights_name" {
  description = "Name of the Application Insights instance"
  type        = string
}

# ── Alerting ────────────────────────────────────────────────────────────────

variable "enable_alerts" {
  description = "Provision the action group and alert rules. Disable for environments where you don't want notifications (e.g. ephemeral CI)."
  type        = bool
  default     = true
}

variable "action_group_name" {
  description = "Name of the action group used by all alert rules."
  type        = string
  default     = "ag-sre-alerts"
}

variable "action_group_short_name" {
  description = "Short name (≤12 chars) shown in SMS / email subjects."
  type        = string
  default     = "sreagent"
  validation {
    condition     = length(var.action_group_short_name) <= 12
    error_message = "action_group_short_name must be 12 characters or fewer."
  }
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

# Severity: 0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose
variable "alert_severity_failed_requests" {
  description = "Severity (0-4) for the failed-requests alert. 0 = Critical."
  type        = number
  default     = 1
}

variable "alert_severity_response_time" {
  description = "Severity (0-4) for the response-time alert."
  type        = number
  default     = 2
}

variable "alert_severity_exception_spike" {
  description = "Severity (0-4) for the exception-spike alert."
  type        = number
  default     = 1
}

variable "failed_requests_threshold" {
  description = "Number of failed requests over a 5-minute window that fires the failure-rate alert. The load generator job runs every 5 minutes and emits a single failed request per run when the bug is active, so the default of 0 (i.e. >0 = fire) catches it on the first cycle."
  type        = number
  default     = 0
}

variable "response_time_threshold_ms" {
  description = "Average request duration (ms) over a 5-minute window that fires the response-time alert."
  type        = number
  default     = 2000
}

variable "exception_spike_threshold" {
  description = "Exception count over a 5-minute window per type that fires the exception-spike alert. The load generator triggers ~1 exception per 5-minute cron run when the bug is active, so the default of 0 (i.e. >0 = fire) catches it."
  type        = number
  default     = 0
}
