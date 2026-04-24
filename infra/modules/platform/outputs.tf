output "container_registry_name" {
  value = azurerm_container_registry.main.name
}

output "container_registry_id" {
  value = azurerm_container_registry.main.id
}

output "container_registry_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "container_app_environment_id" {
  value = azurerm_container_app_environment.main.id
}

output "container_app_environment_name" {
  value = azurerm_container_app_environment.main.name
}

output "container_app_environment_default_domain" {
  value = azurerm_container_app_environment.main.default_domain
}
