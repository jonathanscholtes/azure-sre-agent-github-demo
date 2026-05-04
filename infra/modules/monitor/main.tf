# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = var.log_analytics_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = var.application_insights_name
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
}

# ─────────────────────────────────────────────────────────────────────────────
# Alerting — Action Group + Alert Rules
#
# Without alert rules, failures captured by Application Insights are visible
# in dashboards but never escalated. The SRE Agent reacts to fired alerts /
# incidents, so wiring these is what closes the loop from telemetry → action.
# ─────────────────────────────────────────────────────────────────────────────

# Action group — notification target for all alert rules below.
# Add email receivers via var.alert_email_receivers and webhook receivers via
# var.alert_webhook_receivers (e.g. PagerDuty, ServiceNow, Teams connector).
resource "azurerm_monitor_action_group" "main" {
  count               = var.enable_alerts ? 1 : 0
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name

  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_receivers
    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = true
    }
  }
}

# Metric alert — HTTP failure rate
# Fires when the count of failed requests over the evaluation window exceeds
# the threshold. Failed = HTTP 5xx or unhandled exceptions surfaced as failures.
resource "azurerm_monitor_metric_alert" "failed_requests" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${var.application_insights_name}-failed-requests"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights.main.id]
  description         = "HTTP failure rate exceeded threshold (5xx / unhandled exceptions)."
  severity            = var.alert_severity_failed_requests
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = var.failed_requests_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
}

# Metric alert — Response time degradation
# Fires when the average server response time exceeds the threshold (ms).
resource "azurerm_monitor_metric_alert" "response_time" {
  count               = var.enable_alerts ? 1 : 0
  name                = "alert-${var.application_insights_name}-response-time"
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_application_insights.main.id]
  description         = "Average server response time exceeded threshold."
  severity            = var.alert_severity_response_time
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "microsoft.insights/components"
    metric_name      = "requests/duration"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.response_time_threshold_ms
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }
}

# Scheduled query (log) alert — Exception spike detection
# Detects anomalous bursts of exceptions in the last 5 minutes. Catches new
# exception types that wouldn't trip the metric failure-rate alert (e.g.
# background job failures or non-request code paths).
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "exception_spike" {
  count                   = var.enable_alerts ? 1 : 0
  name                    = "alert-${var.application_insights_name}-exception-spike"
  resource_group_name     = var.resource_group_name
  location                = var.location
  description             = "Spike in exception volume detected in Application Insights."
  severity                = var.alert_severity_exception_spike
  evaluation_frequency    = "PT5M"
  window_duration         = "PT5M"
  scopes                  = [azurerm_application_insights.main.id]
  auto_mitigation_enabled = true

  criteria {
    query                   = <<-KQL
      exceptions
      | where timestamp > ago(5m)
      | summarize ExceptionCount = count() by type = tostring(type)
    KQL
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = var.exception_spike_threshold

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.main[0].id]
  }
}
