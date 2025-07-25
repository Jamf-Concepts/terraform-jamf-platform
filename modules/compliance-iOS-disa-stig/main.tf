## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## DISA STIG is not available for iOS 18 yet. Relevant resources are commented out until we can add support.

## Create categories
resource "jamfpro_category" "category_ios17_stig_benchmarks" {
  name     = "iOS 17 - DISA STIG Benchmarks"
  priority = 9
}

# resource "jamfpro_category" "category_ios18_cis_benchmarks" {
#   name     = "iOS 18 - DISA STIG Benchmarks"
#   priority = 9
# }

resource "jamfpro_smart_mobile_device_group" "group_ios17" {
  name = "iOS 17 - DISA STIG"

  criteria {
    name        = "OS Version"
    priority    = 0
    search_type = "like"
    value       = "17."
  }

  criteria {
    name        = "Serial Number"
    priority    = 1
    search_type = "like"
    value       = "111222333444"
  }
}

# resource "jamfpro_smart_mobile_device_group" "group_ios18" {
#   name = "iOS 18 - DISA STIG"

#   criteria {
#     name        = "OS Version"
#     priority    = 0
#     search_type = "like"
#     value       = "18."
#   }

#   criteria {
#     name        = "Serial Number"
#     priority    = 1
#     search_type = "like"
#     value       = "111222333444"
#   }
# }

## Define configuration profile details for iOS 17
locals {
  ios17_stig_dict = {
    "Application Access"            = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-applicationaccess.mobileconfig"
    "Exchange Active Sync Settings" = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-eas.account.mobileconfig"
    "Mail Policy"                   = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-mail.managed.mobileconfig"
    "Password Policy"               = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "config_ios17" {
  for_each           = local.ios17_stig_dict
  name               = "iOS 17 DISA STIG - ${each.key}"
  description        = "To scope this configuration profile, navigate to Smart Device Groups, select the 'iOS 17 - DISA STIG' Smart Group and remove the placeholder serial number criteria."
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  redeploy_on_update = "Newly Assigned"
  category_id        = jamfpro_category.category_ios17_stig_benchmarks.id

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_mobile_devices      = false
    mobile_device_group_ids = [jamfpro_smart_mobile_device_group.group_ios17.id]
  }
}

## Define configuration profile details for iOS 18
# locals {
#   ios18_stig_dict = {
#     "Application Access"            = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-applicationaccess.mobileconfig"
#     "Exchange Active Sync Settings" = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-eas.account.mobileconfig"
#     "Mail Policy"                   = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-mail.managed.mobileconfig"
#     "Password Policy"               = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-mobiledevice.passwordpolicy.mobileconfig"
#   }
# }

# resource "jamfpro_mobile_device_configuration_profile_plist" "config_ios18" {
#   for_each           = local.ios18_stig_dict
#   name               = "iOS 18 DISA STIG - ${each.key}"
#   deployment_method  = "Install Automatically"
#   level              = "Device Level"
#   redeploy_on_update = "Newly Assigned"
#   category_id        = jamfpro_category.category_ios18_stig_benchmarks.id

#   payloads         = file("${each.value}")
#   payload_validate = false

#   scope {
#     all_mobile_devices      = false
#     mobile_device_group_ids = [jamfpro_smart_mobile_device_group.group_ios18.id]
#   }
# }
