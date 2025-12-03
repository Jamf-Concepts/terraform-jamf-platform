## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
    jsc = {
      source                = "danjamf/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}

resource "jamfpro_api_role" "jamfpro_api_role_sync" {
  display_name = "JSC API Role Device Sync"
  privileges   = ["Read Mac Applications", "Read Mobile Devices", "Read Mobile Device Applications", "Read Smart Mobile Device Groups", "Read Static Mobile Device Groups", "Read Computers", "Read Smart Computer Groups", "Read Static Computer Groups"]
}

resource "jamfpro_api_role" "jamfpro_api_role_signalling" {
  display_name = "JSC API Role Signalling"
  privileges   = ["Update Computer Extension Attributes", "Read Computer Extension Attributes", "Delete Computer Extension Attributes", "Create Computer Extension Attributes", "Read Mobile Device Extension Attributes", "Delete Mobile Device Extension Attributes", "Create Mobile Device Extension Attributes", "Update Mobile Devices", "Update Mobile Device Extension Attributes", "Update Computers", "Update User"]
}

resource "jamfpro_api_role" "jamfpro_api_role_deploy" {
  display_name = "JSC API Role Deploy"
  privileges   = ["Create iOS Configuration Profiles", "Create macOS Configuration Profiles"]
}

resource "jamfpro_api_integration" "jamfpro_api_integration_jsc" {
  display_name                  = "JSC API Client"
  enabled                       = true
  access_token_lifetime_seconds = 6000
  authorization_scopes          = [jamfpro_api_role.jamfpro_api_role_sync.display_name, jamfpro_api_role.jamfpro_api_role_signalling.display_name, jamfpro_api_role.jamfpro_api_role_deploy.display_name]
}

data "jamfpro_api_integration" "jamf_pro_api_integration_001_data" {
  id = jamfpro_api_integration.jamfpro_api_integration_jsc.id
}

output "jp_client_id" {
  value = data.jamfpro_api_integration.jamf_pro_api_integration_001_data.client_id
}

output "jp_client_secret" {
  value = data.jamfpro_api_integration.jamf_pro_api_integration_001_data.client_secret
}

/* resource "time_sleep" "wait_60_seconds" {
  depends_on = [jamfpro_api_integration.jamfpro_api_integration_jsc]

  create_duration = "60s"
} */

resource "jsc_uemc" "initial_uemc" {
  domain       = var.jamfpro_instance_url
  clientid     = data.jamfpro_api_integration.jamf_pro_api_integration_001_data.client_id
  clientsecret = data.jamfpro_api_integration.jamf_pro_api_integration_001_data.client_secret
  /* depends_on   = [time_sleep.wait_60_seconds] */
}
