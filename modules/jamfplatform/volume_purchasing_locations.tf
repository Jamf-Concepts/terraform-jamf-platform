# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Volume_Purchasing_Integration.html
#
# Registers the VPP token and syncs to fetch licence and content data from Apple. The encoded token is
# passed in from the root module (file() is called there, not here).
# Mac and Mobile Device apps reference this resource by ID to assign VPP content and licenses to devices and users.

resource "jamfplatform_pro_volume_purchasing_location" "default" {
  name                                      = "Volume Purchasing Location (Managed by Terraform)"
  service_token                             = var.vpp_token_default
  service_token_wo_version                  = 1
  automatically_populate_purchased_content  = true
  send_notification_when_no_longer_assigned = false
  auto_register_managed_users               = true
}
