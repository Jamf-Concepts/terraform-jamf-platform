## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.5"
    }
    jsc = {
      source  = "danjamf/jsctfprovider"
      version = ">= 0.0.15"
    }
  }
}

resource "random_integer" "entropy" {
  min = 10
  max = 999
}

resource "jsc_oktaidp" "okta_idp_base" {
  clientid  = var.tje_okta_clientid
  name      = "Okta IDP Integration"
  orgdomain = var.tje_okta_orgdomain
}

resource "jsc_ap" "all_services" {
  name             = "Jamf Connect ZTNA and Protect [${random_integer.entropy.result}]"
  idptype          = "OKTA"
  oktaconnectionid = jsc_oktaidp.okta_idp_base.id
  privateaccess    = true
  threatdefence    = true
  datapolicy       = true
}

resource "jamfpro_category" "jsc_all_services_profiles" {
  name     = "Jamf Security Cloud - Activation Profiles [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_macos_configuration_profile_plist" "all_services_macos" {
  name                = "Jamf Connect ZTNA + Jamf Protect Threat and Content Control - macOS (Supervised) [${random_integer.entropy.result}]"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  level               = "System"
  category_id         = jamfpro_category.jsc_all_services_profiles.id

  payloads         = jsc_ap.all_services.macosplist
  payload_validate = false

  scope {
    all_computers = false
  }
}

resource "jamfpro_smart_mobile_device_group" "supervised_devices" {
  name = "Supervised Mobile Devices [${random_integer.entropy.result}]"

  criteria {
    name        = "Supervised"
    priority    = 0
    search_type = "is"
    value       = "Supervised"
  }
}

resource "jamfpro_smart_mobile_device_group" "unsupervised_devices" {
  name = "Unsupervised Mobile Devices [${random_integer.entropy.result}]"

  criteria {
    name        = "Supervised"
    priority    = 0
    search_type = "is"
    value       = "Unsupervised"
  }
}

resource "jamfpro_smart_mobile_device_group" "byod" {
  name = "BYOD Mobile Devices [${random_integer.entropy.result}]"

  criteria {
    name        = "Serial Number"
    priority    = 0
    search_type = "like"
    value       = ""
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "all_services_mobile_supervised" {
  name               = "Jamf Connect ZTNA + Jamf Protect Threat and Content Control - Mobile (Supervised) [${random_integer.entropy.result}]"
  description        = "This configuration profile contains all the pieces you'll need to deploy and enforce ZTNA, Network Security, and Content Control. We have also created a Smart Group called 'Supervised Mobile Devices' that you can scope this configuration to. To do so, navigate to the Scope tab, click 'Edit' on the bottom right, click '+Add' and click the 'Mobile Device Groups' tab. From there, you can add the relevant group."
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.jsc_all_services_profiles.id
  redeploy_on_update = "Newly Assigned"

  payloads         = jsc_ap.all_services.supervisedplist
  payload_validate = false

  scope {
    all_mobile_devices = false
    all_jss_users      = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "all_services_mobile_unsupervised" {
  name               = "Jamf Connect ZTNA + Jamf Protect Threat and Content Control - Mobile (Unsupervised) [${random_integer.entropy.result}]"
  description        = "This configuration profile contains all the pieces you'll need to deploy and enforce ZTNA, Network Security, and Content Control. We have also created a Smart Group called 'Unsupervised Mobile Devices' that you can scope this configuration to. To do so, navigate to the Scope tab, click 'Edit' on the bottom right, click '+Add' and click the 'Mobile Device Groups' tab. From there, you can add the relevant group."
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.jsc_all_services_profiles.id
  redeploy_on_update = "Newly Assigned"

  payloads         = jsc_ap.all_services.unsupervisedplist
  payload_validate = false

  scope {
    all_mobile_devices = false
    all_jss_users      = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "all_services_mobile_byod" {
  name               = "Jamf Connect ZTNA + Jamf Protect Threat and Content Control - Mobile (BYOD) [${random_integer.entropy.result}]"
  description        = "This configuration profile contains all the pieces you'll need to deploy and enforce ZTNA, Network Security, and Content Control. We have also created a Smart Group called 'BYOD Mobile Devices' that you can scope this configuration to. To do so, navigate to the Scope tab, click 'Edit' on the bottom right, click '+Add' and click the 'Mobile Device Groups' tab. From there, you can add the relevant group."
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.jsc_all_services_profiles.id
  redeploy_on_update = "Newly Assigned"

  payloads         = jsc_ap.all_services.byodplist
  payload_validate = false

  scope {
    all_mobile_devices = false
    all_jss_users      = false
  }
}
