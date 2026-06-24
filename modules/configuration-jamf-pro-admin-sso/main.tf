## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## This is expressly intended to enable Admin SSO for Jamf Account within Jamf Pro. You could modify this to also setup SAML settings for enrollment as well.
resource "jamfplatform_pro_sso_settings" "adminsso" {
  sso_enabled        = true
  configuration_type = "OIDC"


  oidc_settings = {
    user_mapping                   = "EMAIL"
    jamf_id_authentication_enabled = true
  }
}
