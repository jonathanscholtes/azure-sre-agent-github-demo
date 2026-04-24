locals {
  cosmos_account_name = "cosmos-${var.project_name}-${var.environment_name}-${var.resource_token}"
}

data "azurerm_client_config" "current" {}

# ──────────────────────────────────────────────
# Cosmos DB Account
# ──────────────────────────────────────────────
resource "azurerm_cosmosdb_account" "main" {
  name                = local.cosmos_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  capabilities {
    name = "EnableServerless"
  }
}

# ──────────────────────────────────────────────
# Cosmos DB Database + Containers
# ──────────────────────────────────────────────
resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "ordersdb"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
}

# Orders container — partition key is customerId for efficient per-customer queries
resource "azurerm_cosmosdb_sql_container" "orders" {
  name                = "orders"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_paths = ["/customerId"]

  indexing_policy {
    indexing_mode = "consistent"

    included_path { path = "/customerId/?" }
    included_path { path = "/status/?" }
    included_path { path = "/createdAt/?" }
    excluded_path { path = "/*" }
  }
}

# Customers container — reference data for the demo
resource "azurerm_cosmosdb_sql_container" "customers" {
  name                = "customers"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_paths = ["/id"]

  indexing_policy {
    indexing_mode = "consistent"

    included_path { path = "/name/?" }
    excluded_path { path = "/*" }
  }
}

# ──────────────────────────────────────────────
# Role Assignments — Managed Identity
# ──────────────────────────────────────────────

# Cosmos DB control-plane reader
resource "azurerm_role_assignment" "cosmos_reader" {
  scope                = azurerm_cosmosdb_account.main.id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = var.identity_principal_id
}

# Cosmos DB data-plane read/write (built-in SQL role 00000000-...-0002)
resource "azurerm_cosmosdb_sql_role_assignment" "identity_data_contributor" {
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.identity_principal_id
  scope               = azurerm_cosmosdb_account.main.id
}

# ──────────────────────────────────────────────
# Role Assignments — Deploying User
# ──────────────────────────────────────────────
resource "azurerm_cosmosdb_sql_role_assignment" "user_data_contributor" {
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = data.azurerm_client_config.current.object_id
  scope               = azurerm_cosmosdb_account.main.id
}
