## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create Jamf Protect <> Jamf Pro integration
resource "jamfplatform_pro_jamf_protect" "protect_integration" {
  protect_url  = var.jamfprotect_url
  client_id    = var.jamfprotect_client_id
  password     = var.jamfprotect_client_password
  auto_install = true

  timeouts {
    create = "90s"
  }
}

## Create Category
resource "jamfplatform_pro_category" "category_jamfprotect_security" {
  name = "Security - Jamf Protect"
}

# Create Smart Group and Congfiguration Profile to identify Sequoia Macs and make Jamf Protect a non removable system extension

resource "jamfplatform_device_group" "group_sequoia_computers_jamf_protect" {
  name = "Macs on MacOS Sequoia (Jamf Protect System Extension Enforcement)"
  group_type  = "smart"
  device_type = "computer"

  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "15."
    },
  ]
}

resource "jamfplatform_pro_macos_configuration_profile" "jamfplatform_pro_macos_configuration_profile_jamf_protect_system_extension" {
  general = {
    name                = "Jamf Protect System Extension Enforcement"
    description         = "This configuration profile prevents users from disabling the Jamf Protect System Extension"
    level               = "System"
    redeploy_on_update  = "Newly Assigned"
    distribution_method = "Install Automatically"
    payloads            = file("${path.module}/support_files/non_removable_system_extension_jamf_protect.mobileconfig")
    user_removable      = false
    category_id         = jamfplatform_pro_category.category_jamfprotect_security.id
  }

  scope = {
    targets = {
      all_computers = false
      computer_group_ids = [jamfplatform_device_group.group_sequoia_computers_jamf_protect.jamf_pro_id]
    }
  }
}
