resource "jamfpro_package" "example" {
  package_name          = "MyApp 1.0.0"
  package_file_source   = "/path/to/MyApp-1.0.0.pkg"
  category_id           = "-1"
  info                  = "Internal build of MyApp"
  notes                 = "Uploaded by Terraform"
  priority              = 10
  reboot_required       = false
  fill_user_template    = false
  fill_existing_users   = false
  os_requirements       = "macOS 10.15.7"
  swu                   = false
  self_heal_notify      = false
  os_install            = false
  serial_number         = ""
  suppress_updates      = false
  ignore_conflicts      = false
  suppress_from_dock    = false
  suppress_eula         = false
  suppress_registration = false
  manifest              = ""
  manifest_file_name    = "MyApp-1.0.0.plist"
  hash_type             = "SHA3_512"
  hash_value            = "abc123"
}
