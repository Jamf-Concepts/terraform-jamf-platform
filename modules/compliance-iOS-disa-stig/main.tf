## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create categories
resource "jamfplatform_pro_category" "category_ios17_stig_benchmarks" {
  name     = "iOS 17 - DISA STIG Benchmarks"
  priority = 9
}

resource "jamfplatform_pro_category" "category_ios18_cis_benchmarks" {
  name     = "iOS 18 - DISA STIG Benchmarks"
  priority = 9
}

resource "jamfplatform_device_group" "group_ios17" {
  name = "iOS 17 - DISA STIG"
  group_type  = "smart"
  device_type = "mobile"

  criteria = [
    {
      criteria = "OS Version"
      operator = "like"
      value    = "17."
    },
    {
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444"
    },
  ]
}

resource "jamfplatform_device_group" "group_ios18" {
  name = "iOS 18 - DISA STIG"
  group_type  = "smart"
  device_type = "mobile"

  criteria = [
    {
      criteria = "OS Version"
      operator = "like"
      value    = "18."
    },
    {
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444"
    },
  ]
}

## Define configuration profile details for iOS 17
locals {
  ios17_stig_dict = {
    "Application Access"            = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-applicationaccess.mobileconfig"
    "Exchange Active Sync Settings" = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-eas.account.mobileconfig"
    "Mail Policy"                   = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-mail.managed.mobileconfig"
    "Password Policy"               = "${path.module}/support_files/mobile_configuration_profiles/iOS17_ios_stig-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "config_ios17" {
  for_each           = local.ios17_stig_dict

  general = {
    name               = "iOS 17 DISA STIG - ${each.key}"
    description        = "To scope this configuration profile, navigate to Smart Device Groups, select the 'iOS 17 - DISA STIG' Smart Group and remove the placeholder serial number criteria."
    distribution_method  = "Install Automatically"
    level              = "Device Level"
    redeploy_on_update = "Newly Assigned"
    category_id        = jamfplatform_pro_category.category_ios17_stig_benchmarks.id
    payloads         = file("${each.value}")
  }

  scope = {
    targets = {
      all_mobile_devices = false
      mobile_device_group_ids = [jamfplatform_device_group.group_ios17.jamf_pro_id]
    }
  }
}

# Define configuration profile details for iOS 18
locals {
  ios18_stig_dict = {
    "Application Access"            = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-applicationaccess.mobileconfig"
    "Exchange Active Sync Settings" = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-eas.account.mobileconfig"
    "Mail Policy"                   = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-mail.managed.mobileconfig"
    "Password Policy"               = "${path.module}/support_files/mobile_configuration_profiles/iOS18_ios_stig-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "config_ios18" {
  for_each           = local.ios18_stig_dict

  general = {
    name               = "iOS 18 DISA STIG - ${each.key}"
    distribution_method  = "Install Automatically"
    level              = "Device Level"
    redeploy_on_update = "Newly Assigned"
    category_id        = jamfplatform_pro_category.category_ios18_cis_benchmarks.id
    payloads         = file("${each.value}")
  }

  scope = {
    targets = {
      all_mobile_devices = false
      mobile_device_group_ids = [jamfplatform_device_group.group_ios18.jamf_pro_id]
    }
  }
}
