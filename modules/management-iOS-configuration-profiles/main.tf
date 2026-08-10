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
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.26.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create Categories
resource "jamfplatform_pro_category" "category_restrictions" {
  name     = "Restrictions"
  priority = 9
}

resource "jamfplatform_pro_category" "category_demo" {
  name     = "Demo"
  priority = 9
}


resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_restrict_apple_id_changes" {

  general = {
    name                = "Restrict Apple Account Changes"
    description         = "This restricts the ability to modify account settings for Apple ID"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_restrictions.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/restrict_appleid_changes.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_restrict_airdrop" {

  general = {
    name                = "Restrict AirDrop"
    description         = "This restricts the ability to use AirDrop"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_restrictions.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/restrict_airdrop.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_passcode_requirements" {

  general = {
    name                = "Passcode Requirements"
    description         = "Enforces a non complex 6 digit passcode"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_demo.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/passcode_requirements.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_restrict_erase_all_content_and_settings" {

  general = {
    name                = "Restrict Erase All Content and Settings"
    description         = "Restricts Erase All Content and Settings"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_restrictions.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/restrict_erase_content_and_settings.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_restrict_camera" {

  general = {
    name                = "Restrict Camera"
    description         = "Restricts the Camera in all Use and Apps"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_restrictions.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/restrict_camera.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_restrict_screenshots" {

  general = {
    name                = "Restrict Screenshots"
    description         = "Restricts the Ability to take Screenshots"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_restrictions.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/restrict_screenshots.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_user_enrollment_byod_restrictions" {

  general = {
    name                = "Demo - User Enrollment / BYOD Restrictions"
    description         = "Sets DLP restrictions for User Enrollment / BYOD"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_demo.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/user_enrollment_byod_restrictions.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

## Extension Attribute for Shared Device and Kiosk Mode examples

resource "jamfplatform_pro_mobile_device_extension_attribute" "device_type" {
  name        = "Device Type"
  description = "Select between kiosk, shared, or none for device types"
  data_type   = "STRING"

  input_type = "POPUP"
  popup_menu_choices = [
    "Kiosk Device",
    "Shared Device",
  ]
  inventory_display = "USER_AND_LOCATION"
}

## Smart Groups for Shared Device and Kiosk Mode

resource "jamfplatform_device_group" "device_type_kiosk_mode" {
  name = "Demo - Kiosk Devices"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = jamfplatform_pro_mobile_device_extension_attribute.device_type.name
      operator = "is"
      value    = "Kiosk Device"
    },
  ]
}

resource "jamfplatform_device_group" "device_type_shared_device_mode" {
  name = "Demo - Shared Devices"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = jamfplatform_pro_mobile_device_extension_attribute.device_type.name
      operator = "is"
      value    = "Shared Device"
    },
  ]
}

## Configuration Profiles for Shared Device and Kiosk Mode

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_kiosk_mode" {

  general = {
    name                = "Demo - Kiosk Mode - Safari (Single App Mode)"
    description         = "Places device in Single App Mode for Safari"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_demo.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/kiosk_mode_safari_single_app_mode.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "mobile_device_configuration_profile_shared_device_mode" {

  general = {
    name                = "Demo - Shared Device Mode - Restrictions"
    description         = "Restricts AirDrop, Apple Account changes, Screenshots, Erase, and Camera"
    distribution_method = "Install Automatically"
    level               = "Device Level"
    category_id         = jamfplatform_pro_category.category_demo.id
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/shared_device_restrictions.mobileconfig")
  }
  scope = {
    targets = {
      all_mobile_devices = false
    }
  }
}
