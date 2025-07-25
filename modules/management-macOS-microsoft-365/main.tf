## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Create Microsoft 365 Category
resource "jamfpro_category" "category_microsoft_365" {
  name     = "Microsoft 365"
  priority = 9
}

## Create Microsoft 365 Smart Groups
resource "jamfpro_smart_computer_group" "group_msft_word" {
  name = "Auto Update:  Microsoft Word"
  criteria {
    name        = "Application Title"
    search_type = "like"
    value       = "Microsoft Word"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_msft_excel" {
  name = "Auto Update: Microsoft Excel"
  criteria {
    name        = "Application Title"
    search_type = "like"
    value       = "Microsoft Excel"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_msft_onedrive" {
  name = "Auto Update: Microsoft OneDrive"
  criteria {
    name        = "Application Title"
    search_type = "like"
    value       = "Microsoft Onedrive"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_msft_outlook" {
  name = "Auto Update: Microsoft Outlook"
  criteria {
    name        = "Application Title"
    search_type = "like"
    value       = "Microsoft Outlook"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_msft_powerpoint" {
  name = "Auto Update:  Microsoft PowerPoint"
  criteria {
    name        = "Application Title"
    search_type = "like"
    value       = "Microsoft Powerpoint"
    and_or      = "and"
    priority    = 0
  }
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

resource "jamfpro_smart_computer_group" "group_msft_teams" {
  name = "Auto Update: Microsoft Teams"
  criteria {
    name        = "Application Title"
    search_type = "like"
    value       = "Microsoft Teams"
    and_or      = "and"
    priority    = 0

  }
}

## Create Microsoft 365 App Installers
resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_excel" {
  name            = "Microsoft Excel 365"
  enabled         = true
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfpro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfpro_smart_computer_group.group_msft_excel.id

  install_predefined_config_profiles = false
  trigger_admin_notifications        = false

  notification_settings {
    notification_message  = "A new update is available"
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }

  self_service_settings {
    include_in_featured_category   = true
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"

    categories {
      id       = jamfpro_category.category_microsoft_365.id
      featured = true
    }
  }
}

# resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_edge_365" {
#   name            = "Microsoft Edge"
#   enabled         = true
#   deployment_type = "SELF_SERVICE"
#   update_behavior = "AUTOMATIC"
#   category_id     = jamfpro_category.category_microsoft_365.id
#   site_id         = "-1"
#   smart_group_id  = jamfpro_smart_computer_group.group_msft_edge.id

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
#       id       = jamfpro_category.category_microsoft_365.id
#       featured = true
#     }
#   }
# }

resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_powerpoint_365" {
  name            = "Microsoft PowerPoint 365"
  enabled         = true
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfpro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfpro_smart_computer_group.group_msft_powerpoint.id

  install_predefined_config_profiles = false
  trigger_admin_notifications        = false

  notification_settings {
    notification_message  = "A new update is available"
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }

  self_service_settings {
    include_in_featured_category   = true
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"

    categories {
      id       = jamfpro_category.category_microsoft_365.id
      featured = true
    }
  }
}

resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_outlook_365" {
  name            = "Microsoft Outlook 365"
  enabled         = true
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfpro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfpro_smart_computer_group.group_msft_outlook.id

  install_predefined_config_profiles = false
  trigger_admin_notifications        = false

  notification_settings {
    notification_message  = "A new update is available"
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }

  self_service_settings {
    include_in_featured_category   = true
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"

    categories {
      id       = jamfpro_category.category_microsoft_365.id
      featured = true
    }
  }
}

resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_onedrive_365" {
  name            = "Microsoft OneDrive"
  enabled         = true
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfpro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfpro_smart_computer_group.group_msft_onedrive.id

  install_predefined_config_profiles = false
  trigger_admin_notifications        = false

  notification_settings {
    notification_message  = "A new update is available"
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }

  self_service_settings {
    include_in_featured_category   = true
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"

    categories {
      id       = jamfpro_category.category_microsoft_365.id
      featured = true
    }
  }
}

resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_word_365" {
  name            = "Microsoft Word 365"
  enabled         = true
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfpro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfpro_smart_computer_group.group_msft_word.id

  install_predefined_config_profiles = false
  trigger_admin_notifications        = false

  notification_settings {
    notification_message  = "A new update is available"
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }

  self_service_settings {
    include_in_featured_category   = true
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"

    categories {
      id       = jamfpro_category.category_microsoft_365.id
      featured = true
    }
  }
}

resource "jamfpro_app_installer" "jamfpro_app_installer_microsoft_teams_365" {
  name            = "Microsoft Teams"
  enabled         = true
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = jamfpro_category.category_microsoft_365.id
  site_id         = "-1"
  smart_group_id  = jamfpro_smart_computer_group.group_msft_teams.id

  install_predefined_config_profiles = false
  trigger_admin_notifications        = false

  notification_settings {
    notification_message  = "A new update is available"
    notification_interval = 1
    deadline_message      = "Update deadline approaching"
    deadline              = 1
    quit_delay            = 1
    complete_message      = "Update completed successfully"
    relaunch              = true
    suppress              = false
  }

  self_service_settings {
    include_in_featured_category   = true
    include_in_compliance_category = true
    force_view_description         = true
    description                    = "This applicaton is managed by Jamf Pro"

    categories {
      id       = jamfpro_category.category_microsoft_365.id
      featured = true
    }
  }
}

