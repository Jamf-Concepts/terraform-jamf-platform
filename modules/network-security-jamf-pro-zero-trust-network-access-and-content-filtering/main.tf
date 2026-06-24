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

resource "jsc_ap" "ztna_dp_only" {
  name             = "Jamf Connect ZTNA and Content Filtering"
  idptype          = "OKTA"
  oktaconnectionid = jsc_oktaidp.okta_idp_base.id
  privateaccess    = true
  threatdefence    = false
  datapolicy       = true
}

resource "jamfplatform_pro_macos_configuration_profile" "ztna_dp" {


  depends_on = [jsc_ap.ztna_dp_only]
  general = {
    name                = "Jamf Connect ZTNA and Content Filtering - macOS (Supervised)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    level               = "Computer Level"
    payloads            = jsc_ap.ztna_dp_only.macosplist
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
