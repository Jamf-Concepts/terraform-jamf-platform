resource "jamfplatform_pro_computer_prestage_enrollment" "example" {
  display_name                          = "Standard macOS PreStage"
  mandatory                             = true
  mdm_removable                         = true
  support_phone_number                  = "111-222-3333"
  support_email_address                 = "email@company.com"
  department                            = "IT"
  default_prestage                      = false
  enrollment_site_id                    = "-1"
  keep_existing_site_membership         = false
  keep_existing_location_information    = false
  require_authentication                = false
  prevent_activation_lock               = false
  enable_device_based_activation_lock   = false
  device_enrollment_program_instance_id = "1"
  auto_advance_setup                    = false
  install_profiles_during_setup         = false





  skip_setup_items = {
    biometric      = false
    file_vault     = true
    icloud_storage = true
    siri           = true
  }
  location_information = {
    username      = ""
    realname      = ""
    phone         = ""
    email         = ""
    room          = ""
    position      = ""
    department_id = "-1"
    building_id   = "-1"
  }
  purchasing_information = {
    leased    = false
    purchased = true
    vendor    = "Apple"
  }
  account_settings = {
    payload_configured          = true
    local_admin_account_enabled = true
    admin_username              = "ladmin"
    admin_management_password   = "ChangeMeNow!"
    user_account_type           = "ADMINISTRATOR"
    admin_password_wo_version   = 1
  }
  scope_serial_numbers = []
}
