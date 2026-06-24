resource "jamfplatform_pro_jamf_connect" "example" {
  version              = "2.43.0"
  auto_deployment_type = "MINOR_AND_PATCH_UPDATES"
  profile_id           = "e9224719-906e-4879-b393-f302fa40e89d"
}
