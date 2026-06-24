// Minimal example — name + payload only.
resource "jamfpro_macos_configuration_profile_plist" "minimal" {
  name     = "Minimal Notifications Profile"
  payloads = file("${path.module}/minimal_notifications.mobileconfig")
}

// Full example with scope, exclusions, and self_service.
resource "jamfpro_macos_configuration_profile_plist" "full" {
  name                = "PPPC - Accessibility"
  description         = "Allows Accessibility for Example.app"
  level               = "System"
  distribution_method = "Make Available in Self Service"
  redeploy_on_update  = "Newly Assigned"
  payloads            = file("${path.module}/pppc.mobileconfig")
  payload_validate    = true
  user_removable      = false
  site_id             = 967
  category_id         = 5

  scope {
    all_computers      = false
    all_jss_users      = false
    computer_ids       = [16, 20]
    computer_group_ids = [jamfpro_smart_computer_group.macos_ventura.id]

    exclusions {
      computer_ids       = [21]
      computer_group_ids = [78]
    }
  }

  self_service {
    install_button_text             = "Install"
    self_service_description        = "This is the self service description"
    force_users_to_view_description = true
    feature_on_main_page            = true
    notification                    = true
    notification_subject            = "New Profile Available"
    notification_message            = "A new profile is available for installation."

    self_service_category {
      id         = 10
      display_in = true
      feature_in = true
    }

    self_service_category {
      id         = 5
      display_in = false
      feature_in = true
    }
  }
}
