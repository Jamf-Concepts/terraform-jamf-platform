# Step 2 — add your software update settings blueprint here
resource "jamfplatform_blueprints_blueprint" "software_update" {
  name        = "Software Update Settings"
  description = "Managed by Terraform"
  deployed    = true

  device_groups = [jamfplatform_device_group.test_machines.id]

  software_update_settings = {
    automatic_download                 = "AlwaysOn"
    automatic_install_os_updates       = "AlwaysOn"
    automatic_install_security_updates = "AlwaysOn"
    notifications_enabled              = true
    rapid_security_response_enabled    = true
  }
}

# Step 3 — add your Safari restrictions blueprint here
resource "jamfplatform_blueprints_blueprint" "safari_restrictions" {
  name        = "Safari Restrictions"
  description = "Managed by Terraform"
  deployed    = true

  device_groups = [jamfplatform_device_group.test_machines.id]

  legacy_payloads = [
    {
      payload_type = "com.apple.applicationaccess"
      settings = {
        allowSafariHistoryClearing = false
        allowSafariPrivateBrowsing = false
      }
    }
  ]
}
