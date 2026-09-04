# -----------------------------------------------------------------------------
# Outputs: <CUSTOMER_NAME>
# -----------------------------------------------------------------------------
# Only the values a human has to act on after an apply. Terraform generates the
# reporting integration credentials but they have to be entered into the reporting
# product by hand, so the apply workflow writes them to the run summary (see
# .github/workflows/apply.yaml).
#
# `sensitive = true` keeps the secret out of plan and apply logs. It does not keep
# it out of state.
# -----------------------------------------------------------------------------

output "insights_api_client_id" {
  description = "ID of the reporting integration API client"
  value       = module.protect.insights_api_client_id
}

output "insights_api_client_secret" {
  description = "Password for the reporting integration API client"
  value       = module.protect.insights_api_client_secret
  sensitive   = true
}

output "jamf_pro_server_url" {
  description = "Jamf Pro server URL for this tenant, resolved through the platform environment"
  value       = module.protect.jamf_pro_server_url
}
