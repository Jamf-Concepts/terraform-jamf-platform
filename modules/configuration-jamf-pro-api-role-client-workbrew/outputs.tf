output "workbrew_client_id" {
  description = "Workbrew API Integration Client ID"
  value       = data.jamfpro_api_integration.workbrew_api_integeration_data.client_id
}

output "workbrew_client_secret" {
  description = "Workbrew API Integration Client Secret"
  value       = data.jamfpro_api_integration.workbrew_api_integeration_data.client_secret
  sensitive   = true
}
