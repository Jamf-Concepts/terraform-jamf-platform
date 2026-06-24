resource "jamfplatform_pro_account" "helpdesk" {
  full_name     = "Sam Help Desk"
  password      = "mySecretThing10"
  enabled       = "Enabled"
  access_level  = "Full Access"
  privilege_set = "Custom"

  username            = "sam.helpdesk"
  email_address       = "sam.helpdesk@example.com"
  password_wo_version = 1
  privileges = {
    jamf_pro_server_objects = [
      "Read Computers",
      "Read Mobile Devices",
    ]
    jamf_pro_server_actions = ["Send Computer Remote Lock Command"]
  }
}
