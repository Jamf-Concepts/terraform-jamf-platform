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
  name     = "MS Windows Defender"
  priority = 9
}

## Combined Config Profile with Content Filtering, Notifications, PPPC, Allowed System Extension and Managed Login items
resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_combined" {
  name                = "Windows Defender MacOS Settings"
  description         = ""
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
  description         = ""
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
  name                = "|Customization Required| Microsoft Defender Onboarding Settings"
  description         = "Use the following link to obtain your Onboarding plist https://learn.microsoft.com/en-us/defender-endpoint/mac-jamfpro-policies#step-1-get-the-microsoft-defender-for-endpoint-onboarding-package"
  level               = "System"
  category_id         = jamfpro_category.category_defender.id
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = file("${path.module}/support_files/onboarding.mobileconfig")
  payload_validate    = false
  user_removable      = false

  scope {
    all_computers = false
    all_jss_users = false
  }
}

resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_epsettings" {
  name                = "|Customization Required| Microsoft Defender Endpoint Settings"
  description         = "Endpoint detection settings guide can be found https://learn.microsoft.com/en-us/defender-endpoint/mac-jamfpro-policies#step-3-configure-microsoft-defender-for-endpoint-settings"
  level               = "System"
  category_id         = jamfpro_category.category_defender.id
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = file("${path.module}/support_files/endpointsettings.mobileconfig")
  payload_validate    = false
  user_removable      = false

  scope {
    all_computers = false
    all_jss_users = false
  }
}


## Create Microsoft Defender Appinstaller
resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_defender" {
  name            = "Microsoft Defender"
  enabled         = true
  deployment_type = "INSTALL_AUTOMATICALLY"
  update_behavior = "MANUAL"
  category_id     = jamfpro_category.category_defender.id
  site_id         = "-1"
  smart_group_id  = "1"

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
