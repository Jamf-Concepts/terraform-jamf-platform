resource "jamfpro_mobile_device_prestage_enrollment" "example" {
  display_name                          = "Standard iPad PreStage"
  device_enrollment_program_instance_id = "1"
  mandatory                             = true
  mdm_removable                         = false
  require_authentication                = false
  supervised                            = true
  allow_pairing                         = true
  auto_advance_setup                    = false
  default_prestage                      = false
  enrollment_site_id                    = "-1"
  enrollment_customization_id           = "0"
  prevent_activation_lock               = true
  enable_device_based_activation_lock   = false

  skip_setup_items {
    location    = true
    apple_id    = true
    screen_time = true
    siri        = true
  }

  location_information {
    username = "fieldops"
    realname = "Field Operations"
  }

  purchasing_information {
    purchased = true
    vendor    = "Apple"
  }

  names {
    assign_names_using     = "List of Names"
    manage_names           = true
    device_name_prefix     = "ipad-"
    device_name_suffix     = ""
    device_naming_configured = true
  }
}
