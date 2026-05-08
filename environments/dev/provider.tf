terraform {
  required_version = ">= 1.11.0"

  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.37.0"
    }
    jamfplatform = {
      source  = "Jamf-Concepts/jamfplatform"
      version = ">= 0.16.3"
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

# Jamf Platform provider
#
# Manages resources backed by the Jamf Platform API Gateway (Beta): Blueprints,
# Compliance Benchmarks, Unified Inventory, and other platform-tier resources.
# Authenticated via OAuth 2.0 Client Credentials. Setup happens in Jamf Account
# (account.jamf.com), separate from Jamf Pro's API Roles and Clients.
#
# Ref: https://developer.jamf.com/platform-api/reference/getting-started-with-platform-api
#
# To create an integration (client credentials):
#   1. Sign in to account.jamf.com -> Feedback Program -> enroll in
#      "Platform API Gateway Beta" under Other.
#   2. Navigate to Integrations -> Create integration.
#      Enter a name, select the region matching your tenant, select the
#      tenant(s) to scope, and assign the required permissions
#      (e.g. read:pro:blueprints).
#   3. Copy the client_id and client_secret from the Integration details
#      panel. Store the secret immediately — it is not shown again.
#   4. Copy the tenant_id by clicking the tenant pill in the same panel.
#   5. Set base_url to the regional endpoint matching your tenant:
#        https://us.apigw.jamf.com
#        https://eu.apigw.jamf.com
#        https://apac.apigw.jamf.com
#   6. Supply credentials via terraform.tfvars or environment variables:
#        export TF_VAR_jamfplatform_client_id="..."
#        export TF_VAR_jamfplatform_client_secret="..."
provider "jamfplatform" {
  base_url      = var.jamfplatform_base_url
  tenant_id     = var.jamfplatform_tenant_id
  client_id     = var.jamfplatform_client_id
  client_secret = var.jamfplatform_client_secret
}
