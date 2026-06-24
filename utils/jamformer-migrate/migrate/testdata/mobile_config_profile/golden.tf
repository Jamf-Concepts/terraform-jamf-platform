// Minimal example.
resource "jamfplatform_pro_mobile_device_configuration_profile" "minimal" {
  general = {
    name     = "Minimal Restrictions Profile"
    payloads = file("${path.module}/restrictions.mobileconfig")
  }
}

// Full example with deployment_method, scope, exclusions, and self_service.
resource "jamfplatform_pro_mobile_device_configuration_profile" "full" {


  general = {
    name                = "Restrictions - Block App Store"
    description         = "Prevents users from installing apps via the App Store."
    level               = "Device Level"
    distribution_method = "Make Available in Self Service"
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/restrictions.mobileconfig")
    category_id         = 5
  }
  scope = {
    targets = {
      all_mobile_devices      = false
      mobile_device_ids       = [101, 102]
      mobile_device_group_ids = [jamfplatform_device_group.all_phones.jamf_pro_id]
    }
    exclusions = {
      mobile_device_ids       = [1101]
      mobile_device_group_ids = [1201]
    }
  }
  self_service = {
    self_service_description = "Installs the corporate VPN configuration."
    feature_on_main_page     = true
    categories = [
      {
        id         = 44
        display_in = true
        feature_in = false
      },
    ]
  }
}
