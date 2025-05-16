## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

# Define a resource to use the local-exec provisioner
resource "null_resource" "run_script" {

  triggers = {
    jamfpro_instance_url  = var.jamfpro_instance_url
    jamfpro_client_id     = var.jamfpro_client_id
    jamfpro_client_secret = var.jamfpro_client_secret
  }
  provisioner "local-exec" {
    command = "${path.module}/protectintegrationcreate.sh ${var.jamfpro_instance_url} ${var.jamfpro_client_id} ${var.jamfpro_client_secret} ${var.jamfprotect_url} ${var.jamfprotect_clientID} ${var.jamfprotect_client_password}"
    when    = create
  }

  provisioner "local-exec" {
    command = "${path.module}/protectintegrationdelete.sh ${self.triggers.jamfpro_instance_url} ${self.triggers.jamfpro_client_id} ${self.triggers.jamfpro_client_secret}"
    when    = destroy
  }
}

## Create Category
resource "jamfpro_category" "category_jamfprotect_security" {
  name = "Security - Jamf Protect"
}

# Create Smart Group and Congfiguration Profile to identify Sequoia Macs and make Jamf Protect a non removable system extension

resource "jamfpro_smart_computer_group" "group_sequoia_computers_jamf_protect" {
  name = "Macs on MacOS Sequoia (Jamf Protect System Extension Enforcement) ${var.entropy_string}"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_profile_jamf_protect_system_extension" {
  name                = "Jamf Protect System Extension Enforcement ${var.entropy_string}"
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
