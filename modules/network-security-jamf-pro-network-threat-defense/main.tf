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

resource "jsc_ap" "mtd_only" {
  name             = "Mobile Threat Defense"
  idptype          = "OKTA"
  oktaconnectionid = jsc_oktaidp.okta_idp_base.id
  privateaccess    = false
  threatdefence    = true
  datapolicy       = false
}

resource "jamfpro_macos_configuration_profile_plist" "mtd" {
  name                = "Network Threat Defense - macOS (Supervised)"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  level               = "System"

  payloads         = jsc_ap.mtd_only.macosplist
  payload_validate = false

  scope {
    all_computers = false
  }
  depends_on = [jsc_ap.mtd_only]
}

output "enable_jsc_uemc_output" {
  value = "yes"
}
