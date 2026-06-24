resource "jamfplatform_pro_app_installer" "self_service" {
  name            = "010 Editor"
  deployment_type = "SELF_SERVICE"
  update_behavior = "AUTOMATIC"
  category_id     = "-1"
  site_id         = "-1"
  smart_group_id  = "1"



  app_title_name = "010 Editor"
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
    description                    = "This is an example app deployment"
  }
}

resource "jamfplatform_pro_app_installer" "automatic" {
  name            = "Jamf Composer"
  deployment_type = "INSTALL_AUTOMATICALLY"
  update_behavior = "AUTOMATIC"
  category_id     = "-1"
  site_id         = "-1"
  smart_group_id  = "-1"

  app_title_name = "Jamf Composer"
}
