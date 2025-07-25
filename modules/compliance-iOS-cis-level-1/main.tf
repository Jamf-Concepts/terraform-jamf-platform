## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Create categories
resource "jamfpro_category" "category_ios17_cis_benchmarks" {
  name     = "iOS 17 - CIS Level 1 Benchmarks"
  priority = 9
}

resource "jamfpro_category" "category_ios18_cis_benchmarks" {
  name     = "iOS 18 - CIS Level 1 Benchmarks"
  priority = 9
}

resource "jamfpro_smart_mobile_device_group" "group_ios17" {
  name = "iOS 17 - CIS Level 1"

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

resource "jamfpro_smart_mobile_device_group" "group_ios18" {
  name = "iOS 18 - CIS Level 1"

  criteria {
    name        = "OS Version"
    priority    = 0
    search_type = "like"
    value       = "18."
  }

  criteria {
    name        = "Serial Number"
    priority    = 1
    search_type = "like"
    value       = "111222333444"
  }
}

## Define configuration profile details for iOS 17
locals {
  ios17_cis_lvl1_dict = {
    "Application Access" = "${path.module}/support_files/mobile_configuration_profiles/iOS17_cis_lvl1_enterprise-applicationaccess.mobileconfig"
    "Mail Policy"        = "${path.module}/support_files/mobile_configuration_profiles/iOS17_cis_lvl1_enterprise-mail.managed.mobileconfig"
    "Password Policy"    = "${path.module}/support_files/mobile_configuration_profiles/iOS17_cis_lvl1_enterprise-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "config_ios17" {
  for_each           = local.ios17_cis_lvl1_dict
  name               = "iOS 17 CIS Level 1 - ${each.key}"
  description        = "To scope this configuration profile, navigate to Smart Device Groups, select the 'iOS 17 - CIS Level 1' Smart Group and remove the placeholder serial number criteria."
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  redeploy_on_update = "Newly Assigned"
  category_id        = jamfpro_category.category_ios17_cis_benchmarks.id

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_mobile_devices      = false
    mobile_device_group_ids = [jamfpro_smart_mobile_device_group.group_ios17.id]
  }
}

## Define configuration profile details for iOS 18
locals {
  ios18_cis_lvl1_dict = {
    "Application Access" = "${path.module}/support_files/mobile_configuration_profiles/iOS18_cis_lvl1_enterprise-applicationaccess.mobileconfig"
    "Mail Policy"        = "${path.module}/support_files/mobile_configuration_profiles/iOS18_cis_lvl1_enterprise-mail.managed.mobileconfig"
    "Password Policy"    = "${path.module}/support_files/mobile_configuration_profiles/iOS18_cis_lvl1_enterprise-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "config_ios18" {
  for_each           = local.ios18_cis_lvl1_dict
  name               = "iOS 18 CIS Level 1 - ${each.key}"
  description        = "To scope this configuration profile, navigate to Smart Device Groups, select the 'iOS 18 - CIS Level 1' Smart Group and remove the placeholder serial number criteria."
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  redeploy_on_update = "Newly Assigned"
  category_id        = jamfpro_category.category_ios18_cis_benchmarks.id

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_mobile_devices      = false
    mobile_device_group_ids = [jamfpro_smart_mobile_device_group.group_ios18.id]
  }
}
