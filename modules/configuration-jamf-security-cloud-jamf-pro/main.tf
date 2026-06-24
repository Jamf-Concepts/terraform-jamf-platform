## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = "0.18.0-rc.2"
      configuration_aliases = [jamfplatform.jpro]
    }
    jsc = {
      source                = "Jamf-Concepts/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}

resource "jamfplatform_pro_api_role" "jamfpro_api_role_sync" {
  display_name = "JSC API Role Device Sync"
  privileges = [
    "Read Mac Applications",
    "Read Mobile Devices",
    "Read Mobile Device Applications",
    "Read Smart Mobile Device Groups",
    "Read Static Mobile Device Groups",
    "Read Computers",
    "Read Smart Computer Groups",
    "Create Static Computer Groups",
    "Read Static Computer Groups"
  ]
}

resource "jamfplatform_pro_api_role" "jamfpro_api_role_signalling" {
  display_name = "JSC API Role Signalling"
  privileges = [
    "Create Computer Extension Attributes",
    "Read Computer Extension Attributes",
    "Update Computer Extension Attributes",
    "Delete Computer Extension Attributes",
    "Create Mobile Device Extension Attributes",
    "Read Mobile Device Extension Attributes",
    "Update Mobile Device Extension Attributes",
    "Delete Mobile Device Extension Attributes",
    "Update Mobile Devices",
    "Update Computers",
    "Update User"
  ]
}

resource "jamfplatform_pro_api_role" "jamfpro_api_role_deploy" {
  display_name = "JSC API Role Deploy"
  privileges = [
    "Create iOS Configuration Profiles",
    "Read iOS Configuration Profiles",
    "Update iOS Configuration Profiles",
    "Create macOS Configuration Profiles",
    "Read macOS Configuration Profiles",
    "Update macOS Configuration Profiles",
    "Update Smart Mobile Device Groups",
    "Update Static Mobile Device Groups",
    "Update Smart Computer Groups",
    "Update Static Computer Groups"
  ]
}

resource "jamfplatform_pro_api_client" "jamfpro_api_integration_jsc" {
  display_name                  = "JSC API Client"
  enabled                       = true
  access_token_lifetime_seconds = 6000
  api_roles                     = [jamfplatform_pro_api_role.jamfpro_api_role_sync.display_name, jamfplatform_pro_api_role.jamfpro_api_role_signalling.display_name, jamfplatform_pro_api_role.jamfpro_api_role_deploy.display_name]
  credential_rotation           = "1"
}

output "jp_client_id" {
  value = jamfplatform_pro_api_client.jamfpro_api_integration_jsc.client_id
}

output "jp_client_secret" {
  value     = jamfplatform_pro_api_client.jamfpro_api_integration_jsc.client_secret
  sensitive = true
}

resource "jsc_uemc" "initial_uemc" {
  domain       = var.jamfplatform_base_url
  clientid     = jamfplatform_pro_api_client.jamfpro_api_integration_jsc.client_id
  clientsecret = jamfplatform_pro_api_client.jamfpro_api_integration_jsc.client_secret
}
