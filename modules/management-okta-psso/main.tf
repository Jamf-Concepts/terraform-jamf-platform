## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

resource "jamfpro_category" "okta_psso" {
  name     = "Okta PSSO"
  priority = 9
}

resource "jamfpro_smart_computer_group" "okta_psso_target" {
  name = "Okta PSSO Target Group"
  criteria {
    name        = "Operating System Version"
    search_type = "greater than or equal"
    value       = "14.0"
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

resource "jamfpro_smart_computer_group" "okta_psso_exclusion" {
  name = "Okta PSSO Exclusion Group"
  criteria {
    name        = "Operating System Version"
    search_type = "greater than or equal"
    value       = "14.0"
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = "Application Title"
    search_type = "is"
    value       = "Jamf Connect.app"
    and_or      = "and"
    priority    = 1
  }
}

resource "jamfpro_package" "okta_verify" {
  package_name          = "Okta Verify"
  package_file_source   = "https://sso.tryjamf.com/api/v1/artifacts/OKTA_VERIFY_MACOS/download?releaseChannel=%OKTA_RELEASE_CHANNEL%"
  category_id           = jamfpro_category.okta_psso.id
  fill_user_template    = false
  os_install            = false
  priority              = 1
  reboot_required       = false
  suppress_eula         = false
  suppress_from_dock    = false
  suppress_registration = false
  suppress_updates      = false
}

resource "jamfpro_policy" "install_okta_verify" {
  name                        = "Install Okta Verify"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  category_id                 = jamfpro_category.okta_psso.id

  payloads {
    packages {
      distribution_point = "default"
      package {
        id                          = jamfpro_package.okta_verify.id
        action                      = "Install"
        fill_user_template          = false
        fill_existing_user_template = false
      }
    }
  }

  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfpro_smart_computer_group.okta_psso_target.id]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "okta_device_access_scep" {
  name                = "Okta Device Access SCEP"
  description         = ""
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  payloads            = local.okta_device_access_scep
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.okta_psso.id

  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfpro_smart_computer_group.okta_psso_target.id]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "okta_verify_psso" {
  name                = "Okta Verify for PSSO at Setup"
  description         = ""
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  payloads            = local.okta_verify_psso_setup
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.okta_psso.id

  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfpro_smart_computer_group.okta_psso_target.id]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "okta_verify_psso_app_config" {
  name                = "Okta Verify App Configuration"
  description         = ""
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  payloads            = local.okta_verify_psso_app_config
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.okta_psso.id

  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfpro_smart_computer_group.okta_psso_target.id]
  }
}

