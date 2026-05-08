# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Computer_Configuration_Profiles.html
#
# Profile payloads are read from .mobileconfig files under
# support_files/macos_configuration_profiles/ at plan time via file().
# Edit those files to change payload content — Terraform detects the change
# and pushes an updated profile on the next apply.
# payload_validate = true asks the provider to verify the plist XML before
# sending it to Jamf Pro.

resource "jamfpro_macos_configuration_profile_plist" "microsoft_autoupdate" {
  name                = "Microsoft AutoUpdate (Managed by Terraform)"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/support_files/macos_configuration_profiles/microsoft_autoupdate.mobileconfig")
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.common["applications"].id
  scope {
    all_computers = false
    all_jss_users = false
    computer_group_ids = [
      jamfpro_smart_computer_group_v2.all_managed.id
    ]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "nudge" {
  name                = "Nudge (Managed by Terraform)"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/support_files/macos_configuration_profiles/nudge.mobileconfig")
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.common["applications"].id
  scope {
    all_computers = false
    all_jss_users = false
    computer_group_ids = [
      jamfpro_smart_computer_group_v2.model["laptops"].id
    ]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "security_and_privacy_laptops" {
  name                = "Security and Privacy - Laptops (Managed by Terraform)"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/support_files/macos_configuration_profiles/security_and_privacy_laptops.mobileconfig")
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.common["global"].id
  scope {
    all_computers = false
    all_jss_users = false
    computer_group_ids = [
      jamfpro_smart_computer_group_v2.model["laptops"].id
    ]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "security_and_privacy_desktops" {
  name                = "Security and Privacy - Desktops (Managed by Terraform)"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/support_files/macos_configuration_profiles/security_and_privacy_desktops.mobileconfig")
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.common["global"].id
  scope {
    all_computers = false
    all_jss_users = false
    computer_group_ids = [
      jamfpro_smart_computer_group_v2.model["desktops"].id
    ]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "sso_extension_entra_id" {
  name                = "Single Sign-On Extension - Entra ID (Managed by Terraform)"
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "All"
  payloads            = file("${path.module}/support_files/macos_configuration_profiles/sso_extension_entra_id.mobileconfig")
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.common["global"].id
  scope {
    all_computers = true
    all_jss_users = false
  }
}
