output "workbrew_client_id" {
  description = "Workbrew API Integration Client ID"
  value       = var.include_workbrew_api_role_client == true ? module.configuration-jamf-pro-api-role-client-workbrew[0].workbrew_client_id : null
}

output "workbrew_client_secret" {
  description = "Workbrew API Integration Client Secret"
  value       = var.include_workbrew_api_role_client == true ? module.configuration-jamf-pro-api-role-client-workbrew[0].workbrew_client_secret : null
  sensitive   = true
}