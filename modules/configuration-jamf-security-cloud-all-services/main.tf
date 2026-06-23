## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfplatform.jpro]
    }
    jsc = {
      source                = "Jamf-Concepts/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}

# resource "jsc_oktaidp" "okta_idp_base" {
#   clientid  = var.okta_client_id
#   name      = "Okta IDP Integration"
#   orgdomain = var.okta_org_domain
# }

resource "jsc_ap" "all_services" {
  name    = "Network Threat and Content Control"
  idptype = "NONE"
  # oktaconnectionid = jsc_oktaidp.okta_idp_base.id
  privateaccess = false
  threatdefence = true
  datapolicy    = true
}

resource "jamfplatform_pro_category" "jsc_all_services_profiles" {
  name     = "Jamf Security Cloud - Activation Profiles"
  priority = 9
}

resource "jamfplatform_device_group" "all_macs" {
  name = "All Computers"
  group_type  = "smart"
  device_type = "computer"

  criteria = [
    {
      criteria = "Computer Group"
      operator = "member of"
      value    = "All Managed Clients"
    },
    {
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444"
    },
  ]
}

resource "jamfplatform_pro_macos_configuration_profile" "all_services_macos" {
  general = {
    name                = "Network Threat and Content Control - macOS (Supervised)"
    description         = "This configuration profile contains all the pieces you'll need to deploy and enforce Network Security and Content Control. We have also created a Smart Group called 'All Computers' and scoped this configuration profile to it. To finalize scoping and get this onto devices, navigate to Smart Computer Groups, click on the 'All Computers' group and remove the serial number criteria with the 111222333444555 serial number."
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    level               = "System"
    category_id         = jamfplatform_pro_category.jsc_all_services_profiles.id
    payloads         = jsc_ap.all_services.macosplist
  }

  scope = {
    targets = {
      all_computers = false
      computer_group_ids = [jamfplatform_device_group.all_macs.jamf_pro_id]
    }
  }

  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
}

resource "jamfplatform_device_group" "supervised_devices" {
  name = "Supervised Mobile Devices"
  group_type  = "smart"
  device_type = "mobile"

  criteria = [
    {
      criteria = "Supervised"
      operator = "is"
      value    = "Supervised"
    },
    {
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

# resource "jamfplatform_device_group" "unsupervised_devices" {
#   name = "Unsupervised Mobile Devices"
#   criteria {
#     name        = "Supervised"
#     priority    = 0
#     search_type = "is"
#     value       = "Unsupervised"
#   }
#   criteria {
#     name        = "Serial Number"
#     priority    = 1
#     search_type = "like"
#     value       = "111222333444555"
#   }
# }
# resource "jamfplatform_pro_smart_mobile_device_group" "byod" {
#   name = "BYOD Mobile Devices"
#   criteria {
#     name        = "Serial Number"
#     priority    = 0
#     search_type = "like"
#     value       = ""
#   }
#   criteria {
#     name        = "Serial Number"
#     priority    = 1
#     search_type = "like"
#     value       = "111222333444555"
#   }
# }
resource "jamfplatform_pro_mobile_device_configuration_profile" "all_services_mobile_supervised" {
  general = {
    name               = "Network Threat and Content Control - Mobile (Supervised)"
    description        = "This configuration profile contains all the pieces you'll need to deploy and enforce Network Security and Content Control. We have also created a Smart Group called 'Supervised Mobile Devices' and scoped this configuration profile to it. To finalize scoping and get this onto devices, navigate to Smart Computer Groups, click on the 'Supervised Mobile Devices' group and remove the serial number criteria with the 111222333444555 serial number."
    distribution_method  = "Install Automatically"
    level              = "Device Level"
    category_id        = jamfplatform_pro_category.jsc_all_services_profiles.id
    redeploy_on_update = "Newly Assigned"
    payloads         = jsc_ap.all_services.supervisedplist
  }

  scope = {
    targets = {
      all_mobile_devices = false
      mobile_device_group_ids = [jamfplatform_device_group.supervised_devices.jamf_pro_id]
    }
  }

  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
}
# resource "jamfplatform_pro_mobile_device_configuration_profile" "all_services_mobile_unsupervised" {
  general = {
  }
}