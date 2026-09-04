# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Mobile_Device_Configuration_Profiles.html
#
# The Wi-Fi profile is generated from a template (.mobileconfig.tpl) with
# the SSID and password injected at plan time via templatefile(). This keeps
# the profile structure in version control while allowing values to vary.
# Move ios_wifi_ssid and ios_wifi_password to sensitive variables in
# variables.tf if deploying to a real environment, because locals are stored in
# Terraform state in plaintext.
#
# payload_validate is false for the Wi-Fi profile because the provider's
# plist validator does not handle the rendered template output.

locals {
  wifi_mobileconfig_content = templatefile("${path.module}/support_files/mobile_device_configuration_profiles/wi-fi.mobileconfig.tpl", {
    ios_wifi_ssid     = var.wifi_ssid
    ios_wifi_password = var.wifi_password
  })
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "lock_screen_1_1" {
  general = {
    name               = "Lock Screen Message (Managed by Terraform)"
    deployment_method  = "Install Automatically"
    redeploy_on_update = "Newly Assigned"
    category_id        = jamfplatform_pro_category.common["global"].id
    payloads           = file("${path.module}/support_files/mobile_device_configuration_profiles/lock_screen_message.mobileconfig")
  }

  scope = {
    targets = {
      all_mobile_devices = true
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "sso_extension_entra_id" {
  general = {
    name               = "Single Sign-On Extension - Entra ID (Managed by Terraform)"
    deployment_method  = "Install Automatically"
    redeploy_on_update = "Newly Assigned"
    category_id        = jamfplatform_pro_category.common["global"].id
    payloads           = file("${path.module}/support_files/mobile_device_configuration_profiles/sso_extension_entra_id.mobileconfig")
  }

  scope = {
    targets = {
      all_mobile_devices = true
    }
  }
}

resource "jamfplatform_pro_mobile_device_configuration_profile" "wifi" {
  general = {
    name               = "Wi-Fi - ${var.wifi_ssid} (Managed by Terraform)"
    deployment_method  = "Install Automatically"
    redeploy_on_update = "Newly Assigned"
    payloads           = local.wifi_mobileconfig_content
    category_id        = jamfplatform_pro_category.common["global"].id
  }

  scope = {
    targets = {
      all_mobile_devices = true
    }
  }
}
