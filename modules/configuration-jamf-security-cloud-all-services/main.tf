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

resource "jamfpro_category" "jsc_all_services_profiles" {
  name     = "Jamf Security Cloud - Activation Profiles"
  priority = 9
}

resource "jamfpro_smart_computer_group" "all_macs" {
  name = "All Computers"

  criteria {
    name        = "Computer Group"
    priority    = 0
    search_type = "member of"
    value       = "All Managed Clients"
  }
  criteria {
    name        = "Serial Number"
    priority    = 1
    search_type = "like"
    value       = "111222333444"
  }
}

resource "jamfpro_macos_configuration_profile_plist" "all_services_macos" {
  name                = "Network Threat and Content Control - macOS (Supervised)"
  description         = "This configuration profile contains all the pieces you'll need to deploy and enforce Network Security and Content Control. We have also created a Smart Group called 'All Computers' and scoped this configuration profile to it. To finalize scoping and get this onto devices, navigate to Smart Computer Groups, click on the 'All Computers' group and remove the serial number criteria with the 111222333444555 serial number."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  level               = "System"
  category_id         = jamfpro_category.jsc_all_services_profiles.id

  payloads         = jsc_ap.all_services.macosplist
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.all_macs.id]
  }
  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
}

resource "jamfpro_smart_mobile_device_group" "supervised_devices" {
  name = "Supervised Mobile Devices"

  criteria {
    name        = "Supervised"
    priority    = 0
    search_type = "is"
    value       = "Supervised"
  }
  criteria {
    name        = "Serial Number"
    priority    = 1
    search_type = "like"
    value       = "111222333444555"
  }
}

# resource "jamfpro_smart_mobile_device_group" "unsupervised_devices" {
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

# resource "jamfpro_smart_mobile_device_group" "byod" {
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

resource "jamfpro_mobile_device_configuration_profile_plist" "all_services_mobile_supervised" {
  name               = "Network Threat and Content Control - Mobile (Supervised)"
  description        = "This configuration profile contains all the pieces you'll need to deploy and enforce Network Security and Content Control. We have also created a Smart Group called 'Supervised Mobile Devices' and scoped this configuration profile to it. To finalize scoping and get this onto devices, navigate to Smart Computer Groups, click on the 'Supervised Mobile Devices' group and remove the serial number criteria with the 111222333444555 serial number."
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.jsc_all_services_profiles.id
  redeploy_on_update = "Newly Assigned"

  payloads         = jsc_ap.all_services.supervisedplist
  payload_validate = false

  scope {
    all_mobile_devices      = false
    all_jss_users           = false
    mobile_device_group_ids = [jamfpro_smart_mobile_device_group.supervised_devices.id]
  }
  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
}

# resource "jamfpro_mobile_device_configuration_profile_plist" "all_services_mobile_unsupervised" {
#   name               = "Network Threat and Content Control - Mobile (Unsupervised)"
#   description        = "This configuration profile contains all the pieces you'll need to deploy and enforce Network Security and Content Control. We have also created a Smart Group called 'Unsupervised Mobile Devices' and scoped this configuration profile to it. To finalize scoping and get this onto devices, navigate to Smart Computer Groups, click on the 'Unsupervised Mobile Devices' group and remove the serial number criteria with the 111222333444555 serial number."
#   deployment_method  = "Install Automatically"
#   level              = "Device Level"
#   category_id        = jamfpro_category.jsc_all_services_profiles.id
#   redeploy_on_update = "Newly Assigned"

#   payloads         = jsc_ap.all_services.unsupervisedplist
#   payload_validate = false

#   scope {
#     all_mobile_devices = false
#     all_jss_users      = false
#   }
#   lifecycle {
#     prevent_destroy = false
#     ignore_changes  = all
#   }
# }

# resource "jamfpro_mobile_device_configuration_profile_plist" "all_services_mobile_byod" {
#   name               = "Network Threat and Content Control - Mobile (BYOD)"
#   description        = "This configuration profile contains all the pieces you'll need to deploy and enforce Network Security and Content Control. We have also created a Smart Group called 'BYOD Mobile Devices' and scoped this configuration profile to it. To finalize scoping and get this onto devices, navigate to Smart Computer Groups, click on the 'BYOD Mobile Devices' group and remove the serial number criteria with the 111222333444555 serial number."
#   deployment_method  = "Install Automatically"
#   level              = "Device Level"
#   category_id        = jamfpro_category.jsc_all_services_profiles.id
#   redeploy_on_update = "Newly Assigned"

#   payloads         = jsc_ap.all_services.byodplist
#   payload_validate = false

#   scope {
#     all_mobile_devices = false
#     all_jss_users      = false
#   }
#   lifecycle {
#     prevent_destroy = false
#     ignore_changes  = all
#   }
# }
