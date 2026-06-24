resource "jamfpro_client_checkin" "this" {
  check_in_frequency                  = 30
  create_startup_script               = true
  startup_log                         = true
  startup_ssh                         = true
  startup_policies                    = true
  create_hooks                        = true
  hook_log                            = true
  hook_policies                       = true
  enable_local_configuration_profiles = true
  allow_network_state_change_triggers = true
}
