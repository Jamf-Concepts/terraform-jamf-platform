## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Create Jamf Protect <> Jamf Pro integration
resource "jamfpro_jamf_protect" "protect_integration" {
  protect_url  = var.jamfprotect_url
  client_id    = var.jamfprotect_clientid
  password     = var.jamfprotect_client_password
  auto_install = true

  timeouts {
    create = "90s"
  }
}

## Create Category
resource "jamfpro_category" "category_jamfprotect_security" {
  name = "Security - Jamf Protect"
}

# Create Smart Group and Congfiguration Profile to identify Sequoia Macs and make Jamf Protect a non removable system extension

resource "jamfpro_smart_computer_group" "group_sequoia_computers_jamf_protect" {
  name = "Macs on MacOS Sequoia (Jamf Protect System Extension Enforcement)"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_profile_jamf_protect_system_extension" {
  name                = "Jamf Protect System Extension Enforcement"
  description         = "This configuration profile prevents users from disabling the Jamf Protect System Extension"
  level               = "System"
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = file("${path.module}/support_files/non_removable_system_extension_jamf_protect.mobileconfig")
  payload_validate    = false
  user_removable      = false
  category_id         = jamfpro_category.category_jamfprotect_security.id

  scope {
    all_computers      = false
    all_jss_users      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_computers_jamf_protect.id]
  }
}
