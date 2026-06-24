resource "jamfpro_api_integration" "ci_pipeline" {
  display_name         = "CI Pipeline"
  enabled              = true
  access_token_lifetime_seconds = 300
  authorization_scopes = ["Read Computers", "Update Computers"]
}
