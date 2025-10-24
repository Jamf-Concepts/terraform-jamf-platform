## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
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

resource "jsc_ap" "mtd_dp_only" {
  name             = "Mobile Threat Defense and Content Filtering"
  idptype          = "OKTA"
  oktaconnectionid = jsc_oktaidp.okta_idp_base.id
  privateaccess    = false
  threatdefence    = true
  datapolicy       = true
}

resource "jamfpro_macos_configuration_profile_plist" "mtd_dp" {
  name                = "Network Threat Defense and Content Filtering - macOS (Supervised)"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  level               = "System"

  payloads         = jsc_ap.mtd_dp_only.macosplist
  payload_validate = false

  scope {
    all_computers = false
  }
  depends_on = [jsc_ap.mtd_dp_only]
}

output "enable_jsc_uemc_output" {
  value = "yes"
}
