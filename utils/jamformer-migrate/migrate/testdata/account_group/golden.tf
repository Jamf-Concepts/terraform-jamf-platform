resource "jamfplatform_pro_account_group" "helpdesk" {
  access_level  = "Full Access"
  privilege_set = "Custom"



  display_name   = "Help Desk"
  ldap_server_id = 31
  privileges = {
    jamf_pro_server_objects = [
      "Read Computers",
      "Read Mobile Devices",
    ]
    jamf_pro_server_actions = ["Send Computer Remote Lock Command"]
  }
}
