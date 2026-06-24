resource "jamfpro_account" "helpdesk" {
  name                  = "sam.helpdesk"
  directory_user        = false
  full_name             = "Sam Help Desk"
  password              = "mySecretThing10"
  email                 = "sam.helpdesk@example.com"
  enabled               = "Enabled"
  force_password_change = false
  access_level          = "Full Access"
  privilege_set         = "Custom"

  jss_objects_privileges = [
    "Read Computers",
    "Read Mobile Devices",
  ]
  jss_settings_privileges = ["Read SSO Settings"]
  jss_actions_privileges  = ["Send Computer Remote Lock Command"]
  casper_admin_privileges = []
}
