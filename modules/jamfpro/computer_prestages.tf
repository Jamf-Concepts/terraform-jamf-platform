# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Automated_Device_Enrollment_for_Computers.html
#
# Two ADE prestages are defined:
#   generic       - baseline config, no IdP onboarding
#   entra_id_psso - installs the Entra ID SSO Extension profile and
#                   Company Portal during Setup Assistant, enabling Platform SSO
#
# Both reference jamfpro_device_enrollments.default, so an ADE token is
# required — see device_enrollments.tf and variables.tf.

resource "jamfpro_computer_prestage_enrollment" "generic" {
  display_name                            = "Generic (Managed by Terraform)"
  mandatory                               = true
  mdm_removable                           = false
  support_phone_number                    = ""
  support_email_address                   = ""
  department                              = ""
  default_prestage                        = false
  enrollment_site_id                      = "-1"
  keep_existing_site_membership           = false
  keep_existing_location_information      = false
  require_authentication                  = false
  authentication_prompt                   = ""
  prevent_activation_lock                 = true
  enable_device_based_activation_lock     = false
  device_enrollment_program_instance_id   = jamfpro_device_enrollments.default.id
  anchor_certificates                     = []
  enrollment_customization_id             = "0"
  language                                = ""
  region                                  = ""
  auto_advance_setup                      = false
  install_profiles_during_setup           = false
  prestage_installed_profile_ids          = []
  custom_package_ids                      = []
  custom_package_distribution_point_id    = "-1"
  enable_recovery_lock                    = false
  recovery_lock_password_type             = "MANUAL"
  recovery_lock_password                  = ""
  rotate_recovery_lock_password           = false
  prestage_minimum_os_target_version_type = "MINIMUM_OS_LATEST_MINOR_VERSION"
  minimum_os_specific_version             = ""
  site_id                                 = "-1"
  skip_setup_items {
    biometric                   = false
    terms_of_address            = true
    file_vault                  = false
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
  location_information {
    username      = ""
    realname      = ""
    phone         = ""
    email         = ""
    room          = ""
    position      = ""
    department_id = "-1"
    building_id   = "-1"
  }
  purchasing_information {
    leased             = false
    purchased          = true
    apple_care_id      = ""
    po_number          = ""
    vendor             = ""
    purchase_price     = ""
    life_expectancy    = 0
    purchasing_account = ""
    purchasing_contact = ""
    lease_date         = "1970-01-01"
    po_date            = "1970-01-01"
    warranty_date      = "1970-01-01"
  }
  account_settings {
    payload_configured                           = true
    local_admin_account_enabled                  = false
    admin_username                               = ""
    admin_password                               = ""
    hidden_admin_account                         = false
    local_user_managed                           = false
    user_account_type                            = "ADMINISTRATOR"
    prefill_primary_account_info_feature_enabled = false
    prefill_type                                 = "UNKNOWN"
    prefill_account_full_name                    = ""
    prefill_account_user_name                    = ""
    prevent_prefill_info_from_modification       = false
  }
}

resource "jamfpro_computer_prestage_enrollment" "entra_id_psso" {
  display_name                          = "Entra ID Platform SSO (Managed by Terraform)"
  mandatory                             = true
  mdm_removable                         = false
  support_phone_number                  = ""
  support_email_address                 = ""
  department                            = ""
  default_prestage                      = false
  enrollment_site_id                    = "-1"
  keep_existing_site_membership         = false
  keep_existing_location_information    = false
  require_authentication                = false
  authentication_prompt                 = ""
  prevent_activation_lock               = true
  enable_device_based_activation_lock   = false
  device_enrollment_program_instance_id = jamfpro_device_enrollments.default.id
  anchor_certificates                   = []
  enrollment_customization_id           = "0"
  language                              = ""
  region                                = ""
  auto_advance_setup                    = false
  install_profiles_during_setup         = true
  prestage_installed_profile_ids = [
    jamfpro_macos_configuration_profile_plist.microsoft_autoupdate.id,
    jamfpro_macos_configuration_profile_plist.sso_extension_entra_id.id
  ]
  custom_package_ids = [
    jamfpro_package.default["microsoft_company_portal"].id
  ]
  custom_package_distribution_point_id    = "-2"
  enable_recovery_lock                    = false
  recovery_lock_password_type             = "MANUAL"
  recovery_lock_password                  = ""
  rotate_recovery_lock_password           = false
  prestage_minimum_os_target_version_type = "MINIMUM_OS_LATEST_MINOR_VERSION"
  minimum_os_specific_version             = ""
  site_id                                 = "-1"
  platform_sso_enabled                    = true
  platform_sso_app_bundle_id              = "com.microsoft.CompanyPortalMac"
  skip_setup_items {
    biometric                   = false
    terms_of_address            = true
    file_vault                  = false
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
  location_information {
    username      = ""
    realname      = ""
    phone         = ""
    email         = ""
    room          = ""
    position      = ""
    department_id = "-1"
    building_id   = "-1"
  }
  purchasing_information {
    leased             = false
    purchased          = true
    apple_care_id      = ""
    po_number          = ""
    vendor             = ""
    purchase_price     = ""
    life_expectancy    = 0
    purchasing_account = ""
    purchasing_contact = ""
    lease_date         = "1970-01-01"
    po_date            = "1970-01-01"
    warranty_date      = "1970-01-01"
  }
  account_settings {
    payload_configured                           = true
    local_admin_account_enabled                  = false
    admin_username                               = ""
    admin_password                               = ""
    hidden_admin_account                         = false
    local_user_managed                           = false
    user_account_type                            = "ADMINISTRATOR"
    prefill_primary_account_info_feature_enabled = false
    prefill_type                                 = "UNKNOWN"
    prefill_account_full_name                    = ""
    prefill_account_user_name                    = ""
    prevent_prefill_info_from_modification       = false
  }
}
