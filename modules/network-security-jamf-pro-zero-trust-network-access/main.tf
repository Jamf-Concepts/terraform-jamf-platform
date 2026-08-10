## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.26.0"
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

resource "jsc_ap" "ztna" {
  name             = "Jamf Connect ZTNA"
  idptype          = "OKTA"
  oktaconnectionid = jsc_oktaidp.okta_idp_base.id
  privateaccess    = true
  threatdefence    = false
  datapolicy       = false
}

resource "jamfplatform_pro_macos_configuration_profile" "ztna_macos" {


  depends_on = [jsc_ap.ztna]
  general = {
    name                = "Jamf Connect ZTNA - macOS (Supervised)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    level               = "Computer Level"
    payloads            = jsc_ap.ztna.macosplist
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
