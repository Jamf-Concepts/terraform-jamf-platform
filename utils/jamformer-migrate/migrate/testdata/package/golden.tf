resource "jamfplatform_pro_package" "example" {
  package_file_source  = "/path/to/MyApp-1.0.0.pkg"
  category_id          = "-1"
  info                 = "Internal build of MyApp"
  notes                = "Uploaded by Terraform"
  priority             = 10
  reboot_required      = false
  os_requirements      = "macOS 10.15.7"
  hash_type            = "SHA3_512"
  hash_value           = "abc123"
  display_name         = "MyApp 1.0.0"
  manifest_file_source = "MyApp-1.0.0.plist"
}
