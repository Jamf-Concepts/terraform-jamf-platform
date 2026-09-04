# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Automated_Device_Enrollment_for_Mobile_Devices.html
#
# Default mobile device ADE prestage. References jamfpro_device_enrollments.default,
# so an ADE token is required. See device_enrollments.tf and variables.tf.

resource "jamfplatform_pro_mobile_device_prestage_enrollment" "default" {
  display_name                                 = "Default (Managed by Terraform)"
  mandatory                                    = true
  mdm_removable                                = false
  default_prestage                             = false
  prevent_activation_lock                      = true
  device_enrollment_program_instance_id        = jamfplatform_pro_automated_device_enrollment.default.id
  allow_pairing                                = true
  supervised                                   = true
  configure_device_before_setup_assistant      = true
  timezone                                     = "UTC"
  prestage_minimum_os_target_version_type_ios  = "MINIMUM_OS_LATEST_MINOR_VERSION"
  prestage_minimum_os_target_version_type_ipad = "MINIMUM_OS_LATEST_MINOR_VERSION"
  skip_setup_items = {
    location                = false
    privacy                 = true
    biometric               = false
    software_update         = false
    diagnostics             = true
    imessage_and_facetime   = true
    intelligence            = true
    tv_room                 = true
    passcode                = false
    sim_setup               = true
    screen_time             = true
    restore_completed       = true
    tv_provider_sign_in     = true
    siri                    = true
    restore                 = true
    screen_saver            = true
    home_button_sensitivity = true
    cloud_storage           = true
    action_button           = true
    transfer_data           = true
    enable_lockdown_mode    = true
    zoom                    = true
    preferred_language      = true
    voice_selection         = true
    tv_home_screen_sync     = true
    safety                  = true
    terms_of_address        = true
    express_language        = true
    camera_button           = true
    apple_id                = true
    display_tone            = true
    watch_migration         = true
    update_completed        = false
    appearance              = false
    android                 = true
    payment                 = true
    onboarding              = true
    tos                     = true
    welcome                 = true
    safety_and_handling     = true
    tap_to_setup            = true
    multitasking            = true
    keyboard                = true
    os_showcase             = true
    spoken_language         = true
  }
}
