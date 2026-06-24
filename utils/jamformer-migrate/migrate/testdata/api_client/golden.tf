resource "jamfplatform_pro_api_client" "ci_pipeline" {
  display_name                  = "CI Pipeline"
  enabled                       = true
  access_token_lifetime_seconds = 300
  api_roles                     = ["Read Computers", "Update Computers"]
  credential_rotation           = "1"
}
