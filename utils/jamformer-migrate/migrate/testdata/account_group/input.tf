resource "jamfpro_account_group" "helpdesk" {
  name          = "Help Desk"
  access_level  = "Full Access"
  privilege_set = "Custom"

  site_id = 1

  identity_server_id = 31

  jss_objects_privileges = [
    "Read Computers",
    "Read Mobile Devices",
  ]
  jss_settings_privileges = []
  jss_actions_privileges  = ["Send Computer Remote Lock Command"]
  casper_admin_privileges = []
}
