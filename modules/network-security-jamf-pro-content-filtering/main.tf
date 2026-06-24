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

resource "jsc_oktaidp" "okta_idp_base" {
  clientid  = var.okta_client_id
  name      = "Okta IDP Integration"
  orgdomain = var.okta_org_domain
}

resource "jsc_ap" "content_filtering_only" {
  name             = "Content Filtering"
  idptype          = "OKTA"
  oktaconnectionid = jsc_oktaidp.okta_idp_base.id
  privateaccess    = false
  threatdefence    = false
  datapolicy       = true
}

resource "jamfplatform_pro_macos_configuration_profile" "dp" {


  depends_on = [jsc_ap.content_filtering_only]
  general = {
    name                = "Content Filtering - macOS (Supervised)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    level               = "Computer Level"
    payloads            = jsc_ap.content_filtering_only.macosplist
  }
  scope = {
    targets = {
      all_computers = false
    }
  }
}

output "enable_jsc_uemc_output" {
  value = "yes"
}
