## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## This is expressly intended to enable Admin SSO for Jamf Account within Jamf Pro. You could modify this to also setup SAML settings for enrollment as well.
resource "jamfpro_sso_settings" "adminsso" {
  sso_enabled        = true
  configuration_type = "OIDC"

  oidc_settings {
    user_mapping                   = "EMAIL"
    jamf_id_authentication_enabled = true
  }

  enrollment_sso_config {
    hosts = []
  }
}
