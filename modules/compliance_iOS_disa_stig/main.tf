## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.5"
    }
  }
}

## DISA STIG is not available for iOS 18 yet. Relevant resources are commented out until we can add support.

resource "random_integer" "entropy" {
  min = 10
  max = 999
}

## Create categories
resource "jamfpro_category" "category_ios17_stig_benchmarks" {
  name     = "iOS 17 - DISA STIG Benchmarks [${random_integer.entropy.result}]"
  priority = 9
}

# resource "jamfpro_category" "category_ios18_cis_benchmarks" {
#   name     = "iOS 18 - DISA STIG Benchmarks [${random_integer.entropy.result}]"
#   priority = 9
# }

resource "jamfpro_smart_mobile_device_group" "group_ios17" {
  name = "iOS 17 - DISA STIG [${random_integer.entropy.result}]"

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
#   name = "iOS 18 - DISA STIG [${random_integer.entropy.result}]"

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
    "Application Access"            = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS17_ios_stig-applicationaccess.mobileconfig"
    "Exchange Active Sync Settings" = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS17_ios_stig-eas.account.mobileconfig"
    "Mail Policy"                   = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS17_ios_stig-mail.managed.mobileconfig"
    "Password Policy"               = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS17_ios_stig-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "config_ios17" {
  for_each           = local.ios17_stig_dict
  name               = "iOS 17 DISA STIG - ${each.key} [${random_integer.entropy.result}]"
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
#     "Application Access"            = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS18_ios_stig-applicationaccess.mobileconfig"
#     "Exchange Active Sync Settings" = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS18_ios_stig-eas.account.mobileconfig"
#     "Mail Policy"                   = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS18_ios_stig-mail.managed.mobileconfig"
#     "Password Policy"               = "${var.support_files_path_prefix}modules/compliance_iOS_disa_stig/support_files/mobile_configuration_profiles/iOS18_ios_stig-mobiledevice.passwordpolicy.mobileconfig"
#   }
# }

# resource "jamfpro_mobile_device_configuration_profile_plist" "config_ios18" {
#   for_each           = local.ios18_stig_dict
#   name               = "iOS 18 DISA STIG - ${each.key} [${random_integer.entropy.result}]"
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
