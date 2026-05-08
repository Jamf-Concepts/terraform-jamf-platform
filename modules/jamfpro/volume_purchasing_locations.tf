# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Volume_Purchasing_Integration.html
#
# After Jamf Pro registers the VPP token it starts a sync to fetch
# licence and content data from Apple. The time_sleep resource waits 2 minutes
# before the data source reads the location back, giving that sync time to
# complete. The postcondition on the data source confirms the sleep finished
# before mac_applications.tf and mobile_device_applications.tf consume the
# content list to check for available VPP licences.

resource "jamfpro_volume_purchasing_locations" "default" {
  name                                      = "Volume Purchasing Location (Managed by Terraform)"
  service_token                             = var.vpp_token_default
  automatically_populate_purchased_content  = true
  send_notification_when_no_longer_assigned = false
  auto_register_managed_users               = true
  timeouts {
    create = "2m"
  }
}

resource "time_sleep" "wait_2_minutes" {
  create_duration = "2m"
  triggers = {
    vpp_location_id = jamfpro_volume_purchasing_locations.default.id
  }
}

data "jamfpro_volume_purchasing_locations" "default" {
  id = jamfpro_volume_purchasing_locations.default.id
  lifecycle {
    postcondition {
      condition     = time_sleep.wait_2_minutes.id != null
      error_message = "Volume purchasing location sync did not complete."
    }
  }
}
