/*
Trial Baseline For Mobile Devices
  Passcode requirements
  Hide apple apps
  Restrict airdrop
  Restrict Apple ID changes
  Restrict camera
  Restrict erase all content and settings
  Restrict screenshots
*/

terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

resource "random_integer" "entropy" {
  min = 10
  max = 999
}

## Create Categories
resource "jamfpro_category" "category_restrictions" {
  name     = "Restrictions [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_category" "category_demo" {
  name     = "Demo [${random_integer.entropy.result}]"
  priority = 9
}


resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_restrict_apple_id_changes" {
  name               = "Restrict Apple Account Changes [${random_integer.entropy.result}]"
  description        = "This restricts the ability to modify account settings for Apple ID"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_restrictions.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/restrict_appleid_changes.mobileconfig")

  scope {
    all_mobile_devices = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_restrict_airdrop" {
  name               = "Restrict AirDrop [${random_integer.entropy.result}]"
  description        = "This restricts the ability to use AirDrop"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_restrictions.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/restrict_airdrop.mobileconfig")

  scope {
    all_mobile_devices = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_passcode_requirements" {
  name               = "Passcode Requirements [${random_integer.entropy.result}]"
  description        = "Enforces a non complex 6 digit passcode"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_demo.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/passcode_requirements.mobileconfig")

  scope {
    all_mobile_devices = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_restrict_erase_all_content_and_settings" {
  name               = "Restrict Erase All Content and Settings [${random_integer.entropy.result}]"
  description        = "Restricts Erase All Content and Settings"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_restrictions.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/restrict_erase_content_and_settings.mobileconfig")

  scope {
    all_mobile_devices = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_restrict_camera" {
  name               = "Restrict Camera [${random_integer.entropy.result}]"
  description        = "Restricts the Camera in all Use and Apps"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_restrictions.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/restrict_camera.mobileconfig")

  scope {
    all_mobile_devices = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_restrict_screenshots" {
  name               = "Restrict Screenshots [${random_integer.entropy.result}]"
  description        = "Restricts the Ability to take Screenshots"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_restrictions.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/restrict_screenshots.mobileconfig")

  scope {
    all_mobile_devices = false
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_user_enrollment_byod_restrictions" {
  name               = "Demo - User Enrollment / BYOD Restrictions [${random_integer.entropy.result}]"
  description        = "Sets DLP restrictions for User Enrollment / BYOD"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_demo.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/user_enrollment_byod_restrictions.mobileconfig")

  scope {
    all_mobile_devices = false
  }
}

## Extension Attribute for Shared Device and Kiosk Mode examples

resource "jamfpro_mobile_device_extension_attribute" "device_type" {
  name              = "Device Type [${random_integer.entropy.result}]"
  description       = "Select between kiosk, shared, or none for device types"
  data_type         = "String"
  inventory_display = "User and Location"

  input_type {
    type = "Pop-up Menu"
    popup_choices = [
      "Kiosk Device",
      "Shared Device",
    ]
  }
}

## Smart Groups for Shared Device and Kiosk Mode

resource "jamfpro_smart_mobile_device_group" "device_type_kiosk_mode" {
  name = "Demo - Kiosk Devices [${random_integer.entropy.result}]"

  criteria {
    name        = jamfpro_mobile_device_extension_attribute.device_type.name
    priority    = 0
    search_type = "is"
    value       = "Kiosk Device"
  }
}

resource "jamfpro_smart_mobile_device_group" "device_type_shared_device_mode" {
  name = "Demo - Shared Devices [${random_integer.entropy.result}]"

  criteria {
    name        = jamfpro_mobile_device_extension_attribute.device_type.name
    priority    = 0
    search_type = "is"
    value       = "Shared Device"
  }
}

## Configuration Profiles for Shared Device and Kiosk Mode

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_kiosk_mode" {
  name               = "Demo - Kiosk Mode - Safari (Single App Mode) [${random_integer.entropy.result}]"
  description        = "Places device in Single App Mode for Safari"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_demo.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/kiosk_mode_safari_single_app_mode.mobileconfig")

  scope {
    all_mobile_devices      = false
    mobile_device_group_ids = [jamfpro_smart_mobile_device_group.device_type_kiosk_mode.id]
  }
}

resource "jamfpro_mobile_device_configuration_profile_plist" "mobile_device_configuration_profile_shared_device_mode" {
  name               = "Demo - Shared Device Mode - Restrictions [${random_integer.entropy.result}]"
  description        = "Restricts AirDrop, Apple Account changes, Screenshots, Erase, and Camera"
  deployment_method  = "Install Automatically"
  level              = "Device Level"
  category_id        = jamfpro_category.category_demo.id
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/support_files/shared_device_restrictions.mobileconfig")

  scope {
    all_mobile_devices      = false
    mobile_device_group_ids = [jamfpro_smart_mobile_device_group.device_type_shared_device_mode.id]
  }
}
