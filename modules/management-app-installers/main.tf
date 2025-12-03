## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Iterate over selected App Installers
resource "jamfpro_app_installer" "app_installers" {
  name            = var.app_installer_name
  enabled         = var.enabled
  deployment_type = var.deployment_type
  update_behavior = var.update_behavior
  category_id     = var.category_id
  site_id         = var.site_id
  smart_group_id  = var.smart_group_id

  install_predefined_config_profiles = var.install_predefined_config_profiles
  trigger_admin_notifications        = var.trigger_admin_notifications

  notification_settings {
    notification_message  = "A new ${var.app_installer_name} update is available"
    notification_interval = var.notification_interval
    deadline_message      = var.deadline_message
    deadline              = var.deadline
    quit_delay            = var.quit_delay
    complete_message      = var.complete_message
    relaunch              = var.relaunch
    suppress              = var.suppress
  }

  self_service_settings {
    include_in_featured_category   = var.include_in_featured_category
    include_in_compliance_category = var.include_in_compliance_category
    force_view_description         = var.force_view_description
    description                    = "${var.app_installer_name} is an App provided from your Self Service Provider."
  }
}
