resource "jamfplatform_pro_computer_check_in_settings" "this" {
  check_in_frequency                  = 30
  create_startup_script               = true
  startup_log                         = true
  startup_ssh                         = true
  startup_policies                    = true
  allow_network_state_change_triggers = true
  create_login_hook                   = true
  login_hook_log                      = true
  login_hook_policies                 = true
}
