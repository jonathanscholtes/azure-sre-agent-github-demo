locals {
  backend_container_app_name = "ca-api-${var.project_name}-${var.resource_token}"
  load_generator_job_name    = "job-loadgen-${var.project_name}-${var.resource_token}"
  registry_server            = "${var.container_registry_name}.azurecr.io"
}

data "azurerm_user_assigned_identity" "main" {
  name                = split("/", var.managed_identity_id)[8]
  resource_group_name = var.resource_group_name
}

data "azurerm_application_insights" "main" {
  name                = var.app_insights_name
  resource_group_name = var.resource_group_name
}

data "azurerm_container_registry" "main" {
  name                = var.container_registry_name
  resource_group_name = var.resource_group_name
}

# Grant AcrPull role to managed identity
resource "azurerm_role_assignment" "acr_pull" {
  scope                = data.azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = data.azurerm_user_assigned_identity.main.principal_id
}

# ──────────────────────────────────────────────
# Backend API Container App
# ──────────────────────────────────────────────
resource "azurerm_container_app" "backend" {
  name                         = local.backend_container_app_name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  registry {
    server   = local.registry_server
    identity = var.managed_identity_id
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 1
    max_replicas = 5

    container {
      name   = "backend-api"
      image  = var.container_app_api_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = data.azurerm_application_insights.main.connection_string
      }
      env {
        name  = "APPINSIGHTS_INSTRUMENTATIONKEY"
        value = data.azurerm_application_insights.main.instrumentation_key
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = data.azurerm_user_assigned_identity.main.client_id
      }
      env {
        name  = "COSMOSDB_ENDPOINT"
        value = var.cosmosdb_endpoint
      }
      env {
        name  = "COSMOSDB_DATABASE"
        value = "ordersdb"
      }
      env {
        name  = "WEBSITES_PORT"
        value = "8000"
      }

      readiness_probe {
        transport        = "HTTP"
        port             = 8000
        path             = "/health"
        interval_seconds = 10
        initial_delay    = 10
      }

      liveness_probe {
        transport        = "HTTP"
        port             = 8000
        path             = "/health"
        interval_seconds = 30
        initial_delay    = 15
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

# ──────────────────────────────────────────────
# Synthetic Load Generator — Container Apps Job
#
# Runs on a cron schedule to produce a steady mix of healthy traffic
# and the seeded ZeroDivisionError, ensuring App Insights always has
# fresh telemetry for the Azure SRE Agent to investigate.
# ──────────────────────────────────────────────
resource "azurerm_container_app_job" "load_generator" {
  name                         = local.load_generator_job_name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  location                     = var.location

  # Run every 5 minutes
  schedule_trigger_config {
    cron_expression          = "*/5 * * * *"
    parallelism              = 1
    replica_completion_count = 1
  }

  replica_timeout_in_seconds = 120
  replica_retry_limit        = 0

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  registry {
    server   = local.registry_server
    identity = var.managed_identity_id
  }

  template {
    container {
      name   = "load-generator"
      image  = var.container_app_loadgen_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "API_URL"
        value = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
      }
      env {
        name  = "ERROR_COUNT"
        value = "3"
      }
      env {
        name  = "LOAD_COUNT"
        value = "10"
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull, azurerm_container_app.backend]

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}
