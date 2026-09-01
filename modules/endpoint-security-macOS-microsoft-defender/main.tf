## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.26.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Data Source
data "http" "defender_combined" {
  url = "https://raw.githubusercontent.com/microsoft/mdatp-xplat/refs/heads/master/macos/mobileconfig/combined/mdatp.mobileconfig"
}

## Create Categories
resource "jamfplatform_pro_category" "category_defender" {
  name     = "Microsoft Defender"
  priority = 9
}

## Create Smart Group for scoping Microsoft Defender
resource "jamfplatform_device_group" "microsoft_defender_target" {
  name        = "Microsoft Defender Target Group"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than or equal"
      value    = "13.0"
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

## Combined Config Profile with Content Filtering, Notifications, PPPC, Allowed System Extension and Managed Login items
resource "jamfplatform_pro_macos_configuration_profile" "jamfpro_macos_configuration_combined" {

  general = {
    name                = "Microsoft Defender MacOS Settings"
    description         = "This will configure all necessary settings for Microsoft Defender for Endpoint on macOS including Content Filtering, Notifications, PPPC, Allowed System Extensions and Managed Login Items. For more information, please see: https://learn.microsoft.com/en-us/defender-endpoint/mac-jamfpro-policies#step-2-create-and-deploy-microsoft-defender-for-endpoint-configuration-profiles"
    level               = "Computer Level"
    category_id         = jamfplatform_pro_category.category_defender.id
    redeploy_on_update  = "Newly Assigned"
    distribution_method = "Install Automatically"
    payloads            = data.http.defender_combined.response_body
    user_removable      = false
  }
  scope = {
    targets = {
      all_computers = true
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "jamfpro_macos_configuration_mau" {

  general = {
    name                = "Microsoft Defender Auto Update Settings"
    description         = "Configuration profile to manage Microsoft Defender for Endpoint auto update settings on macOS devices."
    level               = "Computer Level"
    category_id         = jamfplatform_pro_category.category_defender.id
    redeploy_on_update  = "Newly Assigned"
    distribution_method = "Install Automatically"
    payloads            = file("${path.module}/support_files/defendermau.mobileconfig")
    user_removable      = false
  }
  scope = {
    targets = {
      all_computers = true
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "jamfpro_macos_configuration_onboarding" {

  general = {
    name                = "Microsoft Defender Onboarding Settings"
    description         = "This profile contains the Microsoft Defender for Endpoint onboarding configuration for macOS devices."
    level               = "Computer Level"
    category_id         = jamfplatform_pro_category.category_defender.id
    redeploy_on_update  = "Newly Assigned"
    distribution_method = "Install Automatically"
    payloads            = local.defender_onboarding_profile
    user_removable      = false
  }
  scope = {
    targets = {
      all_computers = true
    }
  }
}


## jamfplatform_pro_app_installer was dropped from the provider in v0.29.0-rc.4
## (PR #335 -- reverse-engineered surface with no published spec). The
## Microsoft Defender App Installer resource that used to live here is now
## provisioned directly against the Jamf Pro API by modular_onboarder's
## utils/jamf_app_installers.py, outside Terraform. The category/device group
## above are unaffected and stay as-is.
