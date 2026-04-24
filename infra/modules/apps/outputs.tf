output "backend_container_app_url" {
  value = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
}

output "backend_container_app_name" {
  value = azurerm_container_app.backend.name
}

output "load_generator_job_name" {
  value = azurerm_container_app_job.load_generator.name
}
