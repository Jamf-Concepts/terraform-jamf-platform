// Minimal example — name + payload only.
resource "jamfplatform_pro_macos_configuration_profile" "minimal" {
  general = {
    name     = "Minimal Notifications Profile"
    payloads = file("${path.module}/minimal_notifications.mobileconfig")
  }
}

// Full example with scope, exclusions, and self_service.
resource "jamfplatform_pro_macos_configuration_profile" "full" {


  general = {
    name                = "PPPC - Accessibility"
    description         = "Allows Accessibility for Example.app"
    level               = "System"
    distribution_method = "Make Available in Self Service"
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/pppc.mobileconfig")
    user_removable      = false
    category_id         = 5
  }
  scope = {
    targets = {
      all_computers      = false
      computer_ids       = [16, 20]
      computer_group_ids = [jamfplatform_device_group.macos_ventura.jamf_pro_id]
    }
    exclusions = {
      computer_ids       = [21]
      computer_group_ids = [78]
    }
  }
  self_service = {
    install_button_text           = "Install"
    self_service_description      = "This is the self service description"
    ensure_users_view_description = true
    feature_on_main_page          = true
    notification                  = true
    notification_subject          = "New Profile Available"
    notification_message          = "A new profile is available for installation."
    categories = [
      {
        id         = 10
        display_in = true
        feature_in = true
      },
      {
        id         = 5
        display_in = false
        feature_in = true
      },
    ]
  }
}
