resource "jamfplatform_pro_jamf_protect" "settings" {
  client_id           = "supersecretclientid"
  password            = "supersecretpassword"
  auto_install        = true
  api_url             = "https://myinstance.protect.jamfcloud.com/graphql"
  password_wo_version = 1
}
