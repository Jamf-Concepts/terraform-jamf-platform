# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Device_Enrollment_Program_Instances.html
#
# Registers the ABM/ASM device management service token with Jamf Pro. The encoded token is
# passed in from the root module (filebase64() is called there, not here).
# Computer and mobile device prestages reference this resource by ID.

resource "jamfpro_device_enrollments" "default" {
  name          = "Default (Managed by Terraform)"
  encoded_token = var.ade_token_encoded_default
}
