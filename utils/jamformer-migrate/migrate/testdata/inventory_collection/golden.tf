resource "jamfplatform_pro_computer_inventory_collection_settings" "example" {

  application_paths {
    path = "/Applications/Custom/App1"
  }
  application_paths {
    path = "/Applications/Custom/App2"
  }
  collect_application_usage_information            = false
  collect_package_receipts                         = true
  collect_available_software_updates               = false
  collect_local_user_accounts                      = true
  include_home_directory_sizes                     = false
  collect_active_directory_mobile_account_info     = false
  collect_beacons                                  = false
  collect_user_and_location_from_directory_service = true
  allow_jamf_binary_user_and_location_changes      = true
  use_unix_user_paths                              = true
}
