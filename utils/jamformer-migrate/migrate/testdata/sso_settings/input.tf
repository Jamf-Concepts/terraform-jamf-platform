resource "jamfpro_sso_settings" "saml_example" {
  sso_enabled                                          = true
  configuration_type                                   = "SAML"
  sso_bypass_allowed                                   = true
  sso_for_enrollment_enabled                           = true
  sso_for_macos_self_service_enabled                   = true
  enrollment_sso_for_account_driven_enrollment_enabled = false
  group_enrollment_access_enabled                      = false
  group_enrollment_access_name                         = ""

  oidc_settings {
    user_mapping = "EMAIL"
  }

  saml_settings {
    token_expiration_disabled = true
    user_mapping              = "EMAIL"
    group_attribute_name      = "http://schemas.xmlsoap.org/claims/Group"
    idp_provider_type         = "AZURE"
    idp_url                   = "https://example.idp.com/sso/saml/metadata"
    entity_id                 = "saml/metadata"
    metadata_source           = "URL"
    session_timeout           = 480
  }

  enrollment_sso_config {
    hosts = []
  }
}
