## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create categories
resource "jamfplatform_pro_category" "category_ssoe" {
  name     = "IdP & SSO"
  priority = 9
}

## Create scripts
resource "jamfplatform_pro_script" "script_ssoe-okta" {
  name     = "SSOe-(Okta)"
  priority = "AFTER"
  info     = "This script will check for the presence of the Okta Verify App. If not present, it will download and install the latest version. It will then launch the app with the the URL of the Experience Jamf Okta tenant."
  script   = file("${path.module}/support_files/computer_scripts/SSOe-(Okta).zsh")
}

## Create Smart Computer Groups
resource "jamfplatform_device_group" "ssoe-okta" {
  name        = "SSOe-(Okta)"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "15."
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

## Define configuration profiles
locals {
  ssoe-okta_dict = {
    "SSOe-Okta" = "${path.module}/support_files/computer_config_profiles/SSOe-(Okta).mobileconfig"
  }
}


## Create configuration profiles for SSOe Okta (generic)
resource "jamfplatform_pro_macos_configuration_profile" "ssoe-okta" {
  for_each = local.ssoe-okta_dict


  lifecycle {
    prevent_destroy = false
    ignore_changes  = all
  }
  general = {
    name                = "Single Sign On - ${each.key}"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    category_id         = jamfplatform_pro_category.category_ssoe.id
    level               = "System"
    payloads            = file("${each.value}")
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.ssoe-okta.jamf_pro_id]
    }
  }
}


## Create policies
resource "jamfplatform_pro_policy" "policy_ssoe" {



  general = {
    name            = "Enable SSOe (Okta)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Once per computer"
    category_id     = jamfplatform_pro_category.category_ssoe.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.ssoe-okta.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service = false
  }
  scripts = {
    scripts = [
      {
        id       = jamfplatform_pro_script.script_ssoe-okta.id
        priority = "Before"
      },
    ]
  }
  maintenance = {
    recon = true
  }
  restart_options = {
    file_vault_2_reboot            = false
    message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
    minutes_until_reboot           = 5
    no_user_logged_in              = "Do not restart"
    start_reboot_timer_immediately = false
    startup_disk                   = "Current Startup Disk"
    user_logged_in                 = "Do not restart"
  }
}
