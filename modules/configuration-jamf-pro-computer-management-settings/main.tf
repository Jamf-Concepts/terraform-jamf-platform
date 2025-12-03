## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

##Computer Inventory Collection Settings
resource "jamfpro_computer_inventory_collection_settings" "example" {
  computer_inventory_collection_preferences {
    monitor_application_usage                          = true
    include_fonts                                      = true
    include_plugins                                    = true
    include_packages                                   = true
    include_software_updates                           = true
    include_software_id                                = true
    include_accounts                                   = true
    calculate_sizes                                    = true
    include_hidden_accounts                            = true
    include_printers                                   = true
    include_services                                   = true
    collect_synced_mobile_device_info                  = true
    update_ldap_info_on_computer_inventory_submissions = true
    monitor_beacons                                    = true
    allow_changing_user_and_location                   = true
    use_unix_user_paths                                = true
    collect_unmanaged_certificates                     = true
  }

  application_paths {
    path = "/Applications/ExampleApp.app"
  }

  font_paths {
    path = "/Library/Fonts/ExampleFont.ttf"
  }

  plugin_paths {
    path = "/Library/Internet Plug-Ins/ExamplePlugin.plugin"
  }
}

##Computer Check-in Settings
resource "jamfpro_client_checkin" "jamfpro_client_checkin" {
  check_in_frequency                  = 15
  create_startup_script               = true
  startup_log                         = true
  startup_ssh                         = false
  startup_policies                    = true
  create_hooks                        = true
  hook_log                            = true
  hook_policies                       = true
  enable_local_configuration_profiles = true
  allow_network_state_change_triggers = true
}
