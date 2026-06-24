output "workbrew_client_id" {
  description = "Workbrew API Integration Client ID"
  value       = jamfplatform_pro_api_client.workbrew_api_integeration.client_id
}

output "workbrew_client_secret" {
  description = "Workbrew API Integration Client Secret"
  value       = jamfplatform_pro_api_client.workbrew_api_integeration.client_secret
  sensitive   = true
}
