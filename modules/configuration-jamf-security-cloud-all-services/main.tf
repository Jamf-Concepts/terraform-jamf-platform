## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.29.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## jsc_ap (Jamf-Concepts/jsctfprovider) is replaced by the native
## jamfplatform_security_cloud_activation_profile resource below -- no more
## hand-built plist payloads or a manual "remove the placeholder serial number
## criteria" cleanup step. The deploy action creates and scopes the Jamf Pro
## configuration profile itself; this module no longer creates one directly.

resource "jamfplatform_pro_category" "jsc_all_services_profiles" {
  name     = "Jamf Security Cloud - Activation Profiles"
  priority = 9
}

resource "jamfplatform_device_group" "all_macs" {
  name        = "All Computers"
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

resource "jamfplatform_device_group" "supervised_devices" {
  name        = "Supervised Mobile Devices"
  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Supervised"
      operator = "is"
      value    = "Supervised"
    },
  ]
}

resource "jamfplatform_security_cloud_activation_profile" "all_services" {
  name      = "Network Threat and Content Control"
  platforms = ["ios", "mac"]

  capabilities = {
    content_controls = true
    network_security = true
  }
}

action "jamfplatform_security_cloud_activation_profile_deploy" "macos" {
  config {
    activation_profile_code = jamfplatform_security_cloud_activation_profile.all_services.id
    os                       = "macos"
    jamf_pro_group_ids       = [jamfplatform_device_group.all_macs.jamf_pro_id]
  }
}

action "jamfplatform_security_cloud_activation_profile_deploy" "supervised_ios" {
  config {
    activation_profile_code = jamfplatform_security_cloud_activation_profile.all_services.id
    os                       = "ios_supervised"
    jamf_pro_group_ids       = [jamfplatform_device_group.supervised_devices.jamf_pro_id]
  }
}

## The deploy actions need the UEM Connect integration (a sibling module) to
## already exist and be connected -- nothing in the action's own arguments
## names it, so ordering comes from depends_on on the resource that triggers
## them. uem_connect_dependency is just that resource's id, passed through
## from the sibling module purely to establish the dependency edge.
resource "terraform_data" "deploy_activation_profile" {
  input = var.uem_connect_dependency

  lifecycle {
    action_trigger {
      events = [after_create]
      actions = [
        action.jamfplatform_security_cloud_activation_profile_deploy.macos,
        action.jamfplatform_security_cloud_activation_profile_deploy.supervised_ios,
      ]
    }
  }
}
