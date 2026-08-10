## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.26.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

##Computer Inventory Collection Settings
resource "jamfplatform_pro_computer_inventory_collection_settings" "example" {
  collect_application_usage_information            = true
  collect_package_receipts                         = true
  collect_available_software_updates               = true
  collect_local_user_accounts                      = true
  include_home_directory_sizes                     = true
  collect_user_and_location_from_directory_service = true
  allow_jamf_binary_user_and_location_changes      = true
  use_unix_user_paths                              = true
  collect_unmanaged_certificates                   = true
}

##Computer Check-in Settings
resource "jamfplatform_pro_computer_check_in_settings" "jamfpro_client_checkin" {
  check_in_frequency                  = 15
  create_startup_script               = true
  startup_log                         = true
  startup_ssh                         = false
  startup_policies                    = true
  allow_network_state_change_triggers = true
  create_login_hook                   = true
  login_hook_log                      = true
  login_hook_policies                 = true
}
