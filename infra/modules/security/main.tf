data "azurerm_client_config" "current" {}

# Managed Identity
resource "azurerm_user_assigned_identity" "main" {
  name                = var.managed_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Key Vault
resource "azurerm_key_vault" "main" {
  name                        = var.key_vault_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  rbac_authorization_enabled = true
}

# Grant Key Vault Secrets Officer role to the managed identity
resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Grant Key Vault Secrets Officer role to the current user/service principal
resource "azurerm_role_assignment" "kv_secrets_officer_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
