# Create an API Role and Client in Jamf Pro before running this project:
#   Settings → System → API roles and clients → API Roles
#   Create a role. Use "All" privileges while learning — tighten later.
#
#   Settings → System → API roles and clients → API Clients
#   Create a client, attach the role, generate a secret.
#
# Supply credentials in terraform.tfvars (gitignored) or via environment variables:
#   export TF_VAR_jamfpro_client_id="..."
#   export TF_VAR_jamfpro_client_secret="..."

provider "jamfpro" {
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  auth_method           = "oauth2"
  client_id             = var.jamfpro_client_id
  client_secret         = var.jamfpro_client_secret

  token_refresh_buffer_period_seconds = 30
}
