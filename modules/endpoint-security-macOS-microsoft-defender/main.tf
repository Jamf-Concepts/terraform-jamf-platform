## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Data Source
data "http" "defender_combined" {
  url = "https://raw.githubusercontent.com/microsoft/mdatp-xplat/refs/heads/master/macos/mobileconfig/combined/mdatp.mobileconfig"
}

## Create Categories
resource "jamfpro_category" "category_defender" {
  name     = "Microsoft Defender"
  priority = 9
}

## Create Smart Group for scoping Microsoft Defender
resource "jamfpro_smart_computer_group" "microsoft_defender_target" {
  name = "Microsoft Defender Target Group"
  criteria {
    name        = "Operating System Version"
    search_type = "greater than or equal"
    value       = "13.0"
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = "Serial Number"
    search_type = "like"
    value       = "111222333444555"
    and_or      = "and"
    priority    = 1
  }
}

## Combined Config Profile with Content Filtering, Notifications, PPPC, Allowed System Extension and Managed Login items
resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_combined" {
  name                = "Microsoft Defender MacOS Settings"
  description         = "This will configure all necessary settings for Microsoft Defender for Endpoint on macOS including Content Filtering, Notifications, PPPC, Allowed System Extensions and Managed Login Items. For more information, please see: https://learn.microsoft.com/en-us/defender-endpoint/mac-jamfpro-policies#step-2-create-and-deploy-microsoft-defender-for-endpoint-configuration-profiles"
  level               = "System"
  category_id         = jamfpro_category.category_defender.id
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = data.http.defender_combined.response_body
  payload_validate    = false
  user_removable      = false

  scope {
    all_computers = true
    all_jss_users = false
  }
}

resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_mau" {
  name                = "Microsoft Defender Auto Update Settings"
  description         = "Configuration profile to manage Microsoft Defender for Endpoint auto update settings on macOS devices."
  level               = "System"
  category_id         = jamfpro_category.category_defender.id
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = file("${path.module}/support_files/defendermau.mobileconfig")
  payload_validate    = false
  user_removable      = false

  scope {
    all_computers = true
    all_jss_users = false
  }
}

resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_onboarding" {
  name                = "Microsoft Defender Onboarding Settings"
  description         = "This profile contains the Microsoft Defender for Endpoint onboarding configuration for macOS devices."
  level               = "System"
  category_id         = jamfpro_category.category_defender.id
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = local.defender_onboarding_profile
  payload_validate    = false
  user_removable      = false

  scope {
    all_computers = true
    all_jss_users = false
  }
}


## Create Microsoft Defender Appinstaller
resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_defender" {
  name            = "Microsoft Defender"
  app_title_name  = "Microsoft Defender"
  enabled         = true
  deployment_type = "INSTALL_AUTOMATICALLY"
  update_behavior = "MANUAL"
  category_id     = jamfpro_category.category_defender.id
  site_id         = "-1"
  smart_group_id  = jamfpro_smart_computer_group.microsoft_defender_target.id

  install_predefined_config_profiles = true
  trigger_admin_notifications        = true

  notification_settings {
    notification_message  = ""
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }

  self_service_settings {
    include_in_featured_category   = true
    include_in_compliance_category = false
    force_view_description         = false
    description                    = ""
  }
}
