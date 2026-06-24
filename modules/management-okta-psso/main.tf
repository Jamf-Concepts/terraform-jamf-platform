## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

resource "jamfplatform_pro_category" "okta_psso" {
  name     = "Okta PSSO"
  priority = 9
}

resource "jamfplatform_device_group" "okta_psso_target" {
  name        = "Okta PSSO Target Group"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than or equal"
      value    = "14.0"
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

resource "jamfplatform_device_group" "okta_psso_exclusion" {
  name        = "Okta PSSO Exclusion Group"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than or equal"
      value    = "14.0"
    },
    {
      and_or   = "and"
      criteria = "Application Title"
      operator = "is"
      value    = "Jamf Connect.app"
    },
  ]
}

resource "jamfplatform_pro_package" "okta_verify" {
  package_file_source = "https://sso.tryjamf.com/api/v1/artifacts/OKTA_VERIFY_MACOS/download?releaseChannel=%OKTA_RELEASE_CHANNEL%"
  category_id         = jamfplatform_pro_category.okta_psso.id
  priority            = 1
  reboot_required     = false
  display_name        = "Okta Verify"
}

resource "jamfplatform_pro_policy" "install_okta_verify" {


  general = {
    name                        = "Install Okta Verify"
    enabled                     = true
    trigger_checkin             = true
    trigger_enrollment_complete = true
    category_id                 = jamfplatform_pro_category.okta_psso.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.okta_psso_target.jamf_pro_id]
    }
  }
  packages = {
    distribution_point = "default"
    packages = [
      {
        id                          = jamfplatform_pro_package.okta_verify.id
        action                      = "Install"
        fill_user_template          = false
        fill_existing_user_template = false
      },
    ]
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "okta_device_access_scep" {

  general = {
    name                = "Okta Device Access SCEP"
    description         = ""
    level               = "System"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    payloads            = local.okta_device_access_scep
    user_removable      = false
    category_id         = jamfplatform_pro_category.okta_psso.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.okta_psso_target.jamf_pro_id]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "okta_verify_psso" {

  general = {
    name                = "Okta Verify for PSSO at Setup"
    description         = ""
    level               = "System"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    payloads            = local.okta_verify_psso_setup
    user_removable      = false
    category_id         = jamfplatform_pro_category.okta_psso.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.okta_psso_target.jamf_pro_id]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "okta_verify_psso_app_config" {

  general = {
    name                = "Okta Verify App Configuration"
    description         = ""
    level               = "System"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    payloads            = local.okta_verify_psso_app_config
    user_removable      = false
    category_id         = jamfplatform_pro_category.okta_psso.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.okta_psso_target.jamf_pro_id]
    }
  }
}

