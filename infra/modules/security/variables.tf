variable "key_vault_name" {
  description = "Name of the Azure Key Vault"
  type        = string
}

variable "managed_identity_name" {
  description = "Name of the User Assigned Managed Identity"
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
