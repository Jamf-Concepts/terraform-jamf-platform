## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

resource "random_integer" "entropy" {
  min = 10
  max = 999
}

## Create categories
resource "jamfpro_category" "category_ssoe" {
  name     = "IdP & SSO [${random_integer.entropy.result}]"
  priority = 9
}

## Create scripts
resource "jamfpro_script" "script_ssoe-okta" {
  name            = "SSOe-(Okta) [${random_integer.entropy.result}]"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/computer_scripts/SSOe-(Okta).zsh")
  category_id     = jamfpro_category.category_ssoe.id
  info            = "This script will check for the presence of the Okta Verify App. If not present, it will download and install the latest version. It will then launch the app with the the URL of the Experience Jamf Okta tenant."
}

## Create Smart Computer Groups
resource "jamfpro_smart_computer_group" "ssoe-okta" {
  name = "SSOe-(Okta) [${random_integer.entropy.result}]"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
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

## Define configuration profiles
locals {
  ssoe-okta_dict = {
    "SSOe-Okta" = "${path.module}/support_files/computer_config_profiles/SSOe-(Okta).mobileconfig"
  }
}


## Create configuration profiles for SSOe Okta (generic)
resource "jamfpro_macos_configuration_profile_plist" "ssoe-okta" {
  for_each            = local.ssoe-okta_dict
  name                = "Single Sign On - ${each.key} [${random_integer.entropy.result}]"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_ssoe.id
  level               = "System"

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.ssoe-okta.id]
  }
}


## Create policies
resource "jamfpro_policy" "policy_ssoe" {
  name            = "Enable SSOe (Okta) [${random_integer.entropy.result}]"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.category_ssoe.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.ssoe-okta.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id       = jamfpro_script.script_ssoe-okta.id
      priority = "Before"
    }

    maintenance {
      recon = true
    }

    reboot {
      file_vault_2_reboot            = false
      message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
      minutes_until_reboot           = 5
      no_user_logged_in              = "Do not restart"
      start_reboot_timer_immediately = false
      startup_disk                   = "Current Startup Disk"
      user_logged_in                 = "Do not restart"
    }
  }
}
