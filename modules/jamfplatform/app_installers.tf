# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/App_Installers.html
#
# Microsoft Office apps share configuration via for_each — one App Installer
# record per map entry. Company Portal is defined separately because it uses
# INSTALL_AUTOMATICALLY (silent push to all managed computers) rather than
# SELF_SERVICE, which makes it available but does not force install.

locals {
  microsoft_office_app_names = {
    "word"       = "Microsoft Word 365"
    "excel"      = "Microsoft Excel 365"
    "powerpoint" = "Microsoft PowerPoint 365"
    "outlook"    = "Microsoft Outlook 365"
    "onenote"    = "Microsoft OneNote 365"
    "teams"      = "Microsoft Teams"
  }
}

resource "jamfplatform_pro_app_installer" "microsoft_office" {
  for_each                           = local.microsoft_office_app_names
  app_title_name                     = each.value
  name                               = each.value
  enabled                            = true
  deployment_type                    = "SELF_SERVICE"
  update_behavior                    = "AUTOMATIC"
  category_id                        = jamfplatform_pro_category.common["applications"].id
  smart_group_id                     = jamfplatform_device_group.computers_model["laptops"].jamf_pro_id
  install_predefined_config_profiles = true
}

resource "jamfplatform_pro_app_installer" "microsoft_intune_company_portal" {
  app_title_name                     = "Microsoft Intune Company Portal"
  name                               = "Microsoft Intune Company Portal"
  enabled                            = true
  deployment_type                    = "INSTALL_AUTOMATICALLY"
  update_behavior                    = "AUTOMATIC"
  category_id                        = jamfplatform_pro_category.common["applications"].id
  smart_group_id                     = jamfplatform_device_group.computers_all_managed.jamf_pro_id
  install_predefined_config_profiles = true
  trigger_admin_notifications        = true

  notification_settings = {
    notification_interval = 1
    deadline              = 2
    quit_delay            = 600
    relaunch              = false
    suppress              = false
  }
}
