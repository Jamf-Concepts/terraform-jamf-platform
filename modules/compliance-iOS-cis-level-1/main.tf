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
resource "jamfplatform_pro_category" "category_ios17_cis_benchmarks" {
  name     = "iOS 17 - CIS Level 1 Benchmarks"
  priority = 9
}

resource "jamfplatform_pro_category" "category_ios18_cis_benchmarks" {
  name     = "iOS 18 - CIS Level 1 Benchmarks"
  priority = 9
}

resource "jamfplatform_pro_category" "category_ios26_cis_benchmarks" {
  name     = "iOS 26 - CIS Level 1 Benchmarks"
  priority = 9
}

resource "jamfplatform_device_group" "group_ios17" {
  name = "iOS 17 - CIS Level 1"
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
  name = "iOS 18 - CIS Level 1"
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

resource "jamfplatform_device_group" "group_ios26" {
  name = "iOS 26 - CIS Level 1"
  group_type  = "smart"
  device_type = "mobile"

  criteria = [
    {
      criteria = "OS Version"
      operator = "like"
      value    = "26."
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
  ios17_cis_lvl1_dict = {
    "Application Access" = "${path.module}/support_files/mobile_configuration_profiles/iOS17_cis_lvl1_enterprise-applicationaccess.mobileconfig"
    "Mail Policy"        = "${path.module}/support_files/mobile_configuration_profiles/iOS17_cis_lvl1_enterprise-mail.managed.mobileconfig"
    "Password Policy"    = "${path.module}/support_files/mobile_configuration_profiles/iOS17_cis_lvl1_enterprise-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "config_ios17" {
  for_each           = local.ios17_cis_lvl1_dict

  general = {
    name               = "iOS 17 CIS Level 1 - ${each.key}"
    description        = "To scope this configuration profile, navigate to Smart Device Groups, select the 'iOS 17 - CIS Level 1' Smart Group and remove the placeholder serial number criteria."
    distribution_method  = "Install Automatically"
    level              = "Device Level"
    redeploy_on_update = "Newly Assigned"
    category_id        = jamfplatform_pro_category.category_ios17_cis_benchmarks.id
    payloads         = file("${each.value}")
  }

  scope = {
    targets = {
      all_mobile_devices = false
      mobile_device_group_ids = [jamfplatform_device_group.group_ios17.jamf_pro_id]
    }
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

resource "jamfplatform_pro_mobile_device_configuration_profile" "config_ios18" {
  for_each           = local.ios18_cis_lvl1_dict

  general = {
    name               = "iOS 18 CIS Level 1 - ${each.key}"
    description        = "To scope this configuration profile, navigate to Smart Device Groups, select the 'iOS 18 - CIS Level 1' Smart Group and remove the placeholder serial number criteria."
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

## Define configuration profile details for iOS 26
locals {
  ios26_cis_lvl1_dict = {
    "Application Access" = "${path.module}/support_files/mobile_configuration_profiles/iOS26_cis_lvl1_enterprise-applicationaccess.mobileconfig"
    "Mail Policy"        = "${path.module}/support_files/mobile_configuration_profiles/iOS26_cis_lvl1_enterprise-mail.managed.mobileconfig"
    "Password Policy"    = "${path.module}/support_files/mobile_configuration_profiles/iOS26_cis_lvl1_enterprise-mobiledevice.passwordpolicy.mobileconfig"
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "config_ios26" {
  for_each           = local.ios26_cis_lvl1_dict

  general = {
    name               = "iOS 26 CIS Level 1 - ${each.key}"
    description        = "To scope this configuration profile, navigate to Smart Device Groups, select the 'iOS 26 - CIS Level 1' Smart Group and remove the placeholder serial number criteria."
    distribution_method  = "Install Automatically"
    level              = "Device Level"
    redeploy_on_update = "Newly Assigned"
    category_id        = jamfplatform_pro_category.category_ios26_cis_benchmarks.id
    payloads         = file("${each.value}")
  }

  scope = {
    targets = {
      all_mobile_devices = false
      mobile_device_group_ids = [jamfplatform_device_group.group_ios26.jamf_pro_id]
    }
  }
}
