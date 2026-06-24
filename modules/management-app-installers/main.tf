## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Iterate over selected App Installers
resource "jamfplatform_pro_app_installer" "app_installers" {
  name            = var.app_installer_name
  app_title_name  = var.app_installer_name
  deployment_type = var.deployment_type
  update_behavior = var.update_behavior
  category_id     = var.category_id
  site_id         = var.site_id
  smart_group_id  = var.smart_group_id



  notification_settings = {
    notification_message  = "A new ${var.app_installer_name} update is available"
    notification_interval = var.notification_interval
    deadline_message      = var.deadline_message
    deadline              = var.deadline
    quit_delay            = var.quit_delay
    complete_message      = var.complete_message
    relaunch              = var.relaunch
    suppress              = var.suppress
  }
  self_service_settings = {
    include_in_featured_category   = var.include_in_featured_category
    include_in_compliance_category = var.include_in_compliance_category
    force_view_description         = var.force_view_description
    description                    = "${var.app_installer_name} is an App provided from your Self Service Provider."
  }
}
