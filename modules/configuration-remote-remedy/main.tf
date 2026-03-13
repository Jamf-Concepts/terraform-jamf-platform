## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
    jsc = {
      source  = "jsctf"
      version = "1.0.0"
    }
  }
}

data "jsc_routes" "route" {
  name = "Nearest Data Center"
}

resource "jsc_ztna" "remote_remedy" {
  name = "Jamf Concepts Remote Services"
  hostnames = [
    "*.remoteassist.jamfconcepts.com",
    "*.remoteremedy.jamfconcepts.com"
  ]
  routeid = data.jsc_routes.route.id
}

resource "jsc_ap" "network_relay_profile" {
  name       = "Remote Remedy Network Relay Activation"
  idptype    = "NetworkRelay"
  depends_on = [jsc_ztna.remote_remedy]
}

resource "jamfpro_category" "remote_remedy" {
  name     = "Remote Remedy"
  priority = 9
}

resource "jamfpro_computer_extension_attribute" "remote_remedy_session" {
  name                   = "RemoteRemedySession"
  description            = "Configuration details for the Remote Remedy SSH/ADP service"
  input_type             = "TEXT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
}

resource "jamfpro_script" "remote_remedy" {
  name            = "Remote Remedy Endpoint Client"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/remote_remedy.sh")
  category_id     = jamfpro_category.remote_remedy.id
}

resource "jamfpro_smart_computer_group_v2" "remote_remedy_base_group" {
  name        = "Remote Remedy - Base Group"
  description = "This Smart Group contains all managed Macs that are eligible for the Remote Remedy service. A script and Network Relay configuration is deployed to these devices, but nothing is activated without the Remote Remedy Session Smart Group being applied to the device."
  criteria {
    name        = "Computer Group"
    search_type = "member of"
    value       = "All Managed Clients"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group_v2" "remote_remedy_active_sessions" {
  name        = "Remote Remedy Active Sessions"
  description = "Devices that have an active remote remedy session or had one (that hasn't been cleaned up) will be a member of this group."
  criteria {
    name        = "RemoteRemedySession"
    search_type = "is not"
    value       = ""
    and_or      = "and"
    priority    = 0
  }
  depends_on = [jamfpro_computer_extension_attribute.remote_remedy_session]
}

resource "jamfpro_macos_configuration_profile_plist" "all_services_macos" {
  name                = "Remote Remedy - Network Relay"
  description         = "This is an Activation Profile to enable Network Relay for Remote Remedy. If you are already deploying Network Relay in your organization, you can simply re-deploy with the newly created Jamf Concepts Remote Services Access Policy and you will be good to go."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  level               = "System"
  category_id         = jamfpro_category.remote_remedy.id

  payloads         = jsc_ap.network_relay_profile.macosplist
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group_v2.remote_remedy_active_sessions.id]
  }
  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
  depends_on = [jsc_ap.network_relay_profile]
}
