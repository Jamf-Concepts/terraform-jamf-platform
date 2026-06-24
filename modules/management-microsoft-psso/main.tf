## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = "0.18.0-rc.2"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

resource "jamfplatform_pro_category" "microsoft_psso" {
  name     = "Microsoft Entra PSSO"
  priority = 9
}

resource "jamfplatform_device_group" "microsoft_psso_target" {
  name        = "Microsoft Entra PSSO Target Group"
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
  name        = "Microsoft Entra PSSO Exclusion Group"
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
  package_file_source = "https://go.microsoft.com/fwlink/?linkid=862280"
  file_name           = "CompanyPortal-Installer.pkg"
  category_id         = jamfplatform_pro_category.microsoft_psso.id
  priority            = 1
  reboot_required     = false
  display_name        = "Microsoft_CompanyPortal_Installer"
}

resource "jamfplatform_pro_policy" "install_microsoft_company_portal" {



  general = {
    name                        = "Install Microsoft Company Portal"
    enabled                     = true
    trigger_checkin             = true
    trigger_enrollment_complete = true
    category_id                 = jamfplatform_pro_category.microsoft_psso.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.microsoft_psso_target.jamf_pro_id]
    }
  }
  packages = {
    distribution_point = "default"
    packages = [
      {
        id                          = jamfplatform_pro_package.microsoft_company_portal.id
        action                      = "Install"
        fill_user_template          = false
        fill_existing_user_template = false
      },
    ]
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "microsoft_psso_settings" {

  general = {
    name                = "Microsoft Entra PSSO Settings"
    description         = "Configuration Profile to set Microsoft Entra PSSO settings"
    level               = "Computer Level"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/Microsoft Entra PSSO Settings.mobileconfig")
    user_removable      = false
    category_id         = jamfplatform_pro_category.microsoft_psso.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.microsoft_psso_target.jamf_pro_id]
    }
  }
}