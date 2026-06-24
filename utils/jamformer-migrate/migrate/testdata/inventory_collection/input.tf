resource "jamfpro_computer_inventory_collection_settings" "example" {
  computer_inventory_collection_preferences {
    monitor_application_usage                          = false
    include_packages                                   = true
    include_software_updates                           = false
    include_accounts                                   = true
    calculate_sizes                                    = false
    include_hidden_accounts                            = false
    monitor_beacons                                    = false
    update_ldap_info_on_computer_inventory_submissions = true
    allow_changing_user_and_location                   = true
    use_unix_user_paths                                = true
  }

  application_paths {
    path = "/Applications/Custom/App1"
  }
  application_paths {
    path = "/Applications/Custom/App2"
  }
}
