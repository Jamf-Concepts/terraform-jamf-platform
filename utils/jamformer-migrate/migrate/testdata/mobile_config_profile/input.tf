// Minimal example.
resource "jamfpro_mobile_device_configuration_profile_plist" "minimal" {
  name     = "Minimal Restrictions Profile"
  payloads = file("${path.module}/restrictions.mobileconfig")
}

// Full example with deployment_method, scope, exclusions, and self_service.
resource "jamfpro_mobile_device_configuration_profile_plist" "full" {
  name               = "Restrictions - Block App Store"
  description        = "Prevents users from installing apps via the App Store."
  level              = "Device Level"
  deployment_method  = "Make Available in Self Service"
  redeploy_on_update = "Newly Assigned"
  payloads           = file("${path.module}/restrictions.mobileconfig")
  site_id            = 967
  category_id        = 5

  scope {
    all_mobile_devices      = false
    all_jss_users           = false
    mobile_device_ids       = [101, 102]
    mobile_device_group_ids = [jamfpro_smart_mobile_device_group.all_phones.id]

    exclusions {
      mobile_device_ids       = [1101]
      mobile_device_group_ids = [1201]
    }
  }

  self_service {
    self_service_description = "Installs the corporate VPN configuration."
    feature_on_main_page     = true

    self_service_category {
      id         = 44
      display_in = true
      feature_in = false
    }
  }
}
