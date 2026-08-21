## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.27.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Target every managed Mac, mirroring the device-group pattern used by
## compliance-macOS-cbengine-cis-level-1.
resource "jamfplatform_device_group" "all_macs_software_update" {
  name        = "Software Update Blueprint - All Managed Macs"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Computer Group"
      operator = "member of"
      value    = "All Managed Clients"
    },
  ]
}

resource "jamfplatform_blueprints_blueprint" "software_update" {
  name        = "[Jamf Foundations] macOS Software Update Enforcement"
  description = "Deployed by the Jamf Foundations onboarder. Enforces OS patching via the Jamf Blueprints Software Update Settings component (DDM)."
  deployed    = true

  device_groups = [jamfplatform_device_group.all_macs_software_update.id]

  component_blocks = [
    {
      name = "Software Update Settings"
      software_update_settings = {
        automatic_download                 = "AlwaysOn"
        automatic_install_security_updates = "AlwaysOn"
        automatic_install_os_updates       = "Allowed"
        notifications_enabled              = true
        rapid_security_response_enabled    = true
        deferral_combined_period_days      = 14
        deferral_major_period_days         = 14
        deferral_minor_period_days         = 14
        deferral_system_period_days        = 14
      }
    },
  ]
}
