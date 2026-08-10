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

## Create Categories
resource "jamfplatform_pro_category" "google_chrome_cloud_management" {
  name     = "Google Chrome Cloud Management"
  priority = 9
}

## Create Smart Computer Groups
resource "jamfplatform_device_group" "google_chrome_cloud_management" {
  name        = "Google Chrome Cloud Management Devices"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

## Create Google Chrome Cloud Management Configuration Profile Payload
locals {
  google_chrome_cloud_management_profile_payload = templatefile(
    "${path.module}/support_files/google_chrome_cloud_management.mobileconfig.tpl",
    {
      google_chrome_cloud_management_enrollment_token = var.google_chrome_cloud_management_enrollment_token
    }
  )
}

## Create Google Chrome Cloud Management Configuration Profile
resource "jamfplatform_pro_macos_configuration_profile" "google_chrome_cloud_management" {

  general = {
    name                = "Google Chrome Cloud Management Settings"
    description         = "To customize Google Chrome Enterprise for your organization, check out the Google documentation: https://support.google.com/chrome/a/answer/9771882?hl=en"
    level               = "Computer Level"
    category_id         = jamfplatform_pro_category.google_chrome_cloud_management.id
    redeploy_on_update  = "Newly Assigned"
    distribution_method = "Install Automatically"
    payloads            = local.google_chrome_cloud_management_profile_payload
    user_removable      = false
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.google_chrome_cloud_management.jamf_pro_id]
    }
  }
}

## Create Google Chrome App Installer
resource "jamfplatform_pro_app_installer" "google_chrome" {
  count           = var.include_google_chrome == true || contains(var.app_installers, "Google Chrome") ? 0 : 1
  name            = "Google Chrome"
  app_title_name  = "Google Chrome"
  deployment_type = "INSTALL_AUTOMATICALLY"
  update_behavior = "AUTOMATIC"
  category_id     = jamfplatform_pro_category.google_chrome_cloud_management.id
  site_id         = "-1"
  smart_group_id  = jamfplatform_device_group.google_chrome_cloud_management.jamf_pro_id



  notification_settings = {
    notification_message  = "A new update is available"
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }
  self_service_settings = {
    include_in_featured_category   = true
    include_in_compliance_category = false
    force_view_description         = false
    description                    = "This is an app provided from your Self Service Provider."
  }
}
