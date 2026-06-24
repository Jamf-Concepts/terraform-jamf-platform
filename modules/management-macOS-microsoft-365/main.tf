## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create Microsoft 365 Category
resource "jamfplatform_pro_category" "category_microsoft_365" {
  name     = "Microsoft 365"
  priority = 9
}

## Create Microsoft 365 Smart Groups
resource "jamfplatform_device_group" "group_msft_word" {
  name        = "Auto Update:  Microsoft Word"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Application Title"
      operator = "like"
      value    = "Microsoft Word"
    },
  ]
}

resource "jamfplatform_device_group" "group_msft_excel" {
  name        = "Auto Update: Microsoft Excel"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Application Title"
      operator = "like"
      value    = "Microsoft Excel"
    },
  ]
}

resource "jamfplatform_device_group" "group_msft_onedrive" {
  name        = "Auto Update: Microsoft OneDrive"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Application Title"
      operator = "like"
      value    = "Microsoft Onedrive"
    },
  ]
}

resource "jamfplatform_device_group" "group_msft_outlook" {
  name        = "Auto Update: Microsoft Outlook"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Application Title"
      operator = "like"
      value    = "Microsoft Outlook"
    },
  ]
}

resource "jamfplatform_device_group" "group_msft_powerpoint" {
  name        = "Auto Update:  Microsoft PowerPoint"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Application Title"
      operator = "like"
      value    = "Microsoft Powerpoint"
    },
  ]
}

# resource "jamfpro_smart_computer_group" "group_msft_edge" {
#   name = "Auto Update:  Microsoft Edge"
#   criteria {
#     name        = "Application Title"
#     search_type = "like"
#     value       = "Microsoft Edge"
#     and_or      = "and"
#     priority    = 0
#   }
# }

resource "jamfplatform_device_group" "group_msft_teams" {
  name        = "Auto Update: Microsoft Teams"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Application Title"
      operator = "like"
      value    = "Microsoft Teams"
    },
  ]
}

## Create Microsoft 365 App Installers
resource "jamfplatform_pro_app_installer" "jamfpro_app_installer_microsoft_excel" {
  app_title_name  = "Microsoft Excel 365"
  name            = "Microsoft Excel 365"
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfplatform_pro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfplatform_device_group.group_msft_excel.jamf_pro_id



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
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"
  }
}

# resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_edge_365" {
#   name            = "Microsoft Edge"
#   enabled         = true
#   deployment_type = "SELF_SERVICE"
#   update_behavior = "AUTOMATIC"
#   category_id     = jamfplatform_pro_category.category_microsoft_365.id
#   site_id         = "-1"
#   smart_group_id  = jamfplatform_device_group.group_msft_edge.jamf_pro_id

#   install_predefined_config_profiles = false
#   trigger_admin_notifications        = false

#   notification_settings {
#     notification_message  = "A new update is available"
#     notification_interval = 1
#     deadline_message      = "Update deadline approaching"
#     deadline              = 1
#     quit_delay            = 1
#     complete_message      = "Update completed successfully"
#     relaunch              = true
#     suppress              = false
#   }

#   self_service_settings {
#     include_in_featured_category   = true
#     include_in_compliance_category = true
#     force_view_description         = true
#     description                    = "This applicaton is managed by Jamf Pro"

#     categories {
#       id       = jamfplatform_pro_category.category_microsoft_365.id
#       featured = true
#     }
#   }
# }

resource "jamfplatform_pro_app_installer" "jamfpro_app_installer_microsoft_powerpoint_365" {
  app_title_name  = "Microsoft PowerPoint 365"
  name            = "Microsoft PowerPoint 365"
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfplatform_pro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfplatform_device_group.group_msft_powerpoint.jamf_pro_id



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
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"
  }
}

resource "jamfplatform_pro_app_installer" "jamfpro_app_installer_microsoft_outlook_365" {
  app_title_name  = "Microsoft Outlook 365"
  name            = "Microsoft Outlook 365"
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfplatform_pro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfplatform_device_group.group_msft_outlook.jamf_pro_id



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
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"
  }
}

resource "jamfplatform_pro_app_installer" "jamfpro_app_installer_microsoft_onedrive_365" {
  app_title_name  = "Microsoft OneDrive"
  name            = "Microsoft OneDrive"
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfplatform_pro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfplatform_device_group.group_msft_onedrive.jamf_pro_id



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
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"
  }
}

resource "jamfplatform_pro_app_installer" "jamfpro_app_installer_microsoft_word_365" {
  app_title_name  = "Microsoft Word 365"
  name            = "Microsoft Word 365"
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfplatform_pro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfplatform_device_group.group_msft_word.jamf_pro_id



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
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"
  }
}

resource "jamfplatform_pro_app_installer" "jamfpro_app_installer_microsoft_teams_365" {
  app_title_name  = "Microsoft Teams"
  name            = "Microsoft Teams"
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfplatform_pro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfplatform_device_group.group_msft_teams.jamf_pro_id



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
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"
  }
}

