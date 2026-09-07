output "workbrew_client_id" {
  description = "Workbrew API Integration Client ID -- null: see main.tf, no programmatic path exists to mint this anymore"
  value       = null
}

output "workbrew_client_secret" {
  description = "Workbrew API Integration Client Secret -- null: see main.tf, no programmatic path exists to mint this anymore"
  value       = null
  sensitive   = true
}
