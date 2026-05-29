terraform {
  required_version = ">= 1.11.0"

  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.37.0"
    }
  }
}

# Jamf Pro provider
#
# Manages resources backed by the Classic and Jamf Pro APIs: policies, smart
# groups, configuration profiles, packages, and so on. Authenticated via
# OAuth2 using API Roles and Clients in Jamf Pro.
#
# To create the OAuth2 client in Jamf Pro:
#   1. Settings -> System -> API roles and clients -> API Roles
#      Create a role with the privileges this provider needs (or "All" while
#      you're learning - tighten later).
#   2. API roles and clients -> API Clients
#      Create a client, attach the role above, generate a secret.
#   3. Supply credentials via terraform.tfvars or environment variables:
#        export TF_VAR_jamfpro_client_id="..."
#        export TF_VAR_jamfpro_client_secret="..."
provider "jamfpro" {
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  auth_method           = "oauth2"
  client_id             = var.jamfpro_client_id
  client_secret         = var.jamfpro_client_secret

  # Refresh the OAuth2 token 30 seconds before it expires.
  token_refresh_buffer_period_seconds = 30
}
