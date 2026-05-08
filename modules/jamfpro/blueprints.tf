# https://learn.jamf.com/en-US/bundle/jamf-pro-blueprints-configuration-guide/page/Jamf_Pro_Blueprints_Configuration_Guide.html
#
# Blueprints are Jamf Platform resources but scope to device groups defined
# in Jamf Pro. The jamfpro_group data sources bridge the two providers: they
# look up the Jamf Platform group ID that corresponds to each Jamf Pro smart
# group — the Platform API uses a different ID space from Jamf Pro.
#
# deployed = false creates the blueprint without pushing it to devices.
# Set to true when ready to enforce settings in production.

data "jamfpro_group" "computer_all_managed" {
  group_jamfpro_id = jamfpro_smart_computer_group_v2.all_managed.id
  group_type       = "COMPUTER"
}

data "jamfpro_group" "mobile_device_all_managed" {
  group_jamfpro_id = jamfpro_smart_mobile_device_group_v1.all_managed.id
  group_type       = "MOBILE"
}

data "jamfpro_group" "mobile_device_model" {
  for_each         = jamfpro_smart_mobile_device_group_v1.model
  group_jamfpro_id = each.value.id
  group_type       = "MOBILE"
}


resource "jamfplatform_blueprints_blueprint" "passcode_policy" {
  name        = "Passcode Policy"
  description = "Managed by Terraform"
  deployed    = false

  device_groups = [data.jamfpro_group.mobile_device_model["iphones"].group_platform_id]

  passcode_policy = {
    change_at_next_auth              = true
    failed_attempts_reset_in_minutes = 0
    maximum_failed_attempts          = 11
    maximum_grace_period_in_minutes  = 0
    maximum_inactivity_in_minutes    = 0
    maximum_passcode_age_in_days     = 0
    minimum_complex_characters       = 0
    minimum_length                   = 0
    passcode_reuse_limit             = 1
    require_alphanumeric_passcode    = true
    require_complex_passcode         = true
    require_passcode                 = true
  }
}

resource "jamfplatform_blueprints_blueprint" "software_update_settings" {
  name        = "Software Update Settings"
  description = "Managed by Terraform"
  deployed    = false

  device_groups = concat(
    [data.jamfpro_group.computer_all_managed.group_platform_id],
    [data.jamfpro_group.mobile_device_all_managed.group_platform_id]
  )

  software_update_settings = {
    allow_standard_user_os_updates           = true
    automatic_download                       = "AlwaysOn"
    automatic_install_os_updates             = "AlwaysOn"
    automatic_install_security_updates       = "AlwaysOn"
    deferral_combined_period_days            = 7
    deferral_major_period_days               = 30
    deferral_minor_period_days               = 14
    deferral_system_period_days              = 3
    notifications_enabled                    = true
    rapid_security_response_enabled          = true
    rapid_security_response_rollback_enabled = false
    recommended_cadence                      = "Newest"
  }
}

resource "jamfplatform_blueprints_blueprint" "software_update" {
  name        = "Software Updates - Set and Forget - All Managed Computers and Mobile Devices"
  description = "Managed by Terraform"
  deployed    = false

  device_groups = concat(
    [data.jamfpro_group.computer_all_managed.group_platform_id],
    [data.jamfpro_group.mobile_device_all_managed.group_platform_id]
  )

  software_update = {
    deployment_time       = "17:30"
    enforce_after_days    = 14
    ignore_major_versions = true
  }
}
