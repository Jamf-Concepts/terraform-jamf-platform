# Credentials are supplied via terraform.tfvars — see Prerequisites in README.md

provider "jamfpro" {
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  auth_method           = "oauth2"
  client_id             = var.jamfpro_client_id
  client_secret         = var.jamfpro_client_secret

  token_refresh_buffer_period_seconds = 30
}
