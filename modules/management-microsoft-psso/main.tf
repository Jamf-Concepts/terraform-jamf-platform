## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

resource "jamfpro_category" "microsoft_psso" {
  name     = "Microsoft Entra PSSO"
  priority = 9
}

resource "jamfpro_smart_computer_group" "microsoft_psso_target" {
  name = "Microsoft Entra PSSO Target Group"
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

resource "jamfpro_smart_computer_group" "microsoft_psso_exclusion" {
  name = "Microsoft Entra PSSO Exclusion Group"
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

resource "jamfpro_package" "microsoft_company_portal" {
  package_name          = "Microsoft_CompanyPortal_Installer"
  package_file_source   = "https://go.microsoft.com/fwlink/?linkid=862280"
  category_id           = jamfpro_category.microsoft_psso.id
  fill_user_template    = false
  os_install            = false
  priority              = 1
  reboot_required       = false
  suppress_eula         = false
  suppress_from_dock    = false
  suppress_registration = false
  suppress_updates      = false
}

resource "jamfpro_policy" "install_microsoft_company_portal" {
  name                        = "Install Microsoft Company Portal"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  category_id                 = jamfpro_category.microsoft_psso.id

  payloads {
    packages {
      distribution_point = "default"
      package {
        id                          = jamfpro_package.microsoft_company_portal.id
        action                      = "Install"
        fill_user_template          = false
        fill_existing_user_template = false
      }
    }
  }

  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfpro_smart_computer_group.microsoft_psso_target.id]
  }

}

resource "jamfpro_macos_configuration_profile_plist" "microsoft_psso_settings" {
  name                = "Microsoft Entra PSSO Settings"
  description         = "Configuration Profile to set Microsoft Entra PSSO settings"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  payloads            = file("${path.module}/support_files/Microsoft Entra PSSO Settings.mobileconfig")
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.microsoft_psso.id

  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfpro_smart_computer_group.microsoft_psso_target.id]
  }
}