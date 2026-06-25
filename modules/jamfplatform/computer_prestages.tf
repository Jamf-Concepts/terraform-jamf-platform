# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Automated_Device_Enrollment_for_Computers.html
#
# Two ADE prestages are defined:
#   generic       - baseline config, no IdP onboarding
#   entra_id_psso - installs the Entra ID SSO Extension profile and
#                   Company Portal during Setup Assistant, enabling Platform SSO
#
# Both reference jamfplatform_pro_automated_device_enrollment.default, so an ADE token is
# required — see device_enrollments.tf and variables.tf.
#
# Only non-default values are set. Optional fields left unset (support
# contact details, location/purchasing/account info, recovery lock, etc.)
# fall back to the provider's "unset" behaviour.

resource "jamfplatform_pro_computer_prestage_enrollment" "generic" {
  display_name                            = "Generic (Managed by Terraform)"
  mandatory                               = true
  mdm_removable                           = false
  prevent_activation_lock                 = true
  enable_device_based_activation_lock     = false
  require_authentication                  = false
  keep_existing_site_membership           = false
  keep_existing_location_information      = false
  auto_advance_setup                      = false
  install_profiles_during_setup           = false
  device_enrollment_program_instance_id   = jamfplatform_pro_automated_device_enrollment.default.id
  prestage_minimum_os_target_version_type = "MINIMUM_OS_LATEST_MINOR_VERSION"

  skip_setup_items = {
    biometric                   = false
    terms_of_address            = true
    filevault                   = false
    icloud_diagnostics          = true
    diagnostics                 = true
    accessibility               = false
    apple_id                    = true
    screen_time                 = true
    siri                        = true
    display_tone                = true
    restore                     = true
    appearance                  = false
    privacy                     = true
    payment                     = true
    registration                = true
    tos                         = true
    icloud_storage              = true
    location                    = false
    intelligence                = true
    enable_lockdown_mode        = true
    welcome                     = true
    wallpaper                   = true
    software_update             = true
    additional_privacy_settings = true
    os_showcase                 = true
  }
}

resource "jamfplatform_pro_computer_prestage_enrollment" "entra_id_psso" {
  display_name                            = "Entra ID Platform SSO (Managed by Terraform)"
  mandatory                               = true
  mdm_removable                           = false
  prevent_activation_lock                 = true
  enable_device_based_activation_lock     = false
  require_authentication                  = false
  keep_existing_site_membership           = false
  keep_existing_location_information      = false
  auto_advance_setup                      = false
  install_profiles_during_setup           = true
  device_enrollment_program_instance_id   = jamfplatform_pro_automated_device_enrollment.default.id
  prestage_minimum_os_target_version_type = "MINIMUM_OS_LATEST_MINOR_VERSION"
  psso_enabled                            = true
  platform_sso_app_bundle_id              = "com.microsoft.CompanyPortalMac"
  custom_package_distribution_point_id    = "-2"

  prestage_installed_profile_ids = [
    jamfplatform_pro_macos_configuration_profile.microsoft_autoupdate.id,
    jamfplatform_pro_macos_configuration_profile.sso_extension_entra_id.id
  ]

  custom_package_ids = [
    jamfplatform_pro_package.default["microsoft_company_portal"].id
  ]

  skip_setup_items = {
    biometric                   = false
    terms_of_address            = true
    filevault                   = false
    icloud_diagnostics          = true
    diagnostics                 = true
    accessibility               = false
    apple_id                    = true
    screen_time                 = true
    siri                        = true
    display_tone                = true
    restore                     = true
    appearance                  = false
    privacy                     = true
    payment                     = true
    registration                = true
    tos                         = true
    icloud_storage              = true
    location                    = false
    intelligence                = true
    enable_lockdown_mode        = true
    welcome                     = true
    wallpaper                   = true
    software_update             = true
    additional_privacy_settings = true
    os_showcase                 = true
  }
}
