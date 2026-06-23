## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

resource "jamfplatform_pro_category" "microsoft_psso" {
  name     = "Microsoft Entra PSSO"
  priority = 9
}

resource "jamfplatform_device_group" "microsoft_psso_target" {
  name = "Microsoft Entra PSSO Target Group"
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

resource "jamfplatform_device_group" "microsoft_psso_exclusion" {
  name = "Microsoft Entra PSSO Exclusion Group"
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

resource "jamfplatform_pro_package" "microsoft_company_portal" {
  package_name          = "Microsoft_CompanyPortal_Installer"
  package_file_source   = "https://go.microsoft.com/fwlink/?linkid=862280"
  category_id           = jamfplatform_pro_category.microsoft_psso.id
  fill_user_template    = false
  os_install            = false
  priority              = 1
  reboot_required       = false
  suppress_eula         = false
  suppress_from_dock    = false
  suppress_registration = false
  suppress_updates      = false
}

resource "jamfplatform_pro_policy" "install_microsoft_company_portal" {
  name                        = "Install Microsoft Company Portal"
  enabled                     = true
  trigger_checkin             = true
  trigger_enrollment_complete = true
  category_id                 = jamfplatform_pro_category.microsoft_psso.id

  payloads {
    packages {
      distribution_point = "default"
      package {
        id                          = jamfplatform_pro_package.microsoft_company_portal.id
        action                      = "Install"
        fill_user_template          = false
        fill_existing_user_template = false
      }
    }
  }

  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfplatform_device_group.microsoft_psso_target.jamf_pro_id]
  }

}

resource "jamfplatform_pro_macos_configuration_profile" "microsoft_psso_settings" {
  general = {
    name                = "Microsoft Entra PSSO Settings"
    description         = "Configuration Profile to set Microsoft Entra PSSO settings"
    level               = "System"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/Microsoft Entra PSSO Settings.mobileconfig")
    user_removable      = false
    category_id         = jamfplatform_pro_category.microsoft_psso.id
  }

  scope = {
    targets = {
      all_computers = false
      computer_group_ids = [jamfplatform_device_group.microsoft_psso_target.jamf_pro_id]
    }
  }
}