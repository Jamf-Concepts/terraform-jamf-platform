# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Computer_Configuration_Profiles.html
#
# Profile payloads are read from .mobileconfig files under
# support_files/macos_configuration_profiles/ at plan time via file().
# Edit those files to change payload content. Terraform detects the change
# and pushes an updated profile on the next apply.

resource "jamfplatform_pro_macos_configuration_profile" "microsoft_autoupdate" {
  general = {
    name                = "Microsoft AutoUpdate (Managed by Terraform)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "All"
    payloads            = file("${path.module}/support_files/macos_configuration_profiles/microsoft_autoupdate.mobileconfig")
    category_id         = jamfplatform_pro_category.common["applications"].id
  }
  scope = {
    targets = {
      computer_group_ids = [
        jamfplatform_device_group.computers_all_managed.jamf_pro_id
      ]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "nudge" {
  general = {
    name                = "Nudge (Managed by Terraform)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "All"
    payloads            = file("${path.module}/support_files/macos_configuration_profiles/nudge.mobileconfig")
    category_id         = jamfplatform_pro_category.common["applications"].id
  }
  scope = {
    targets = {
      computer_group_ids = [
        jamfplatform_device_group.computers_model["laptops"].jamf_pro_id
      ]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "security_and_privacy_laptops" {
  general = {
    name                = "Security and Privacy - Laptops (Managed by Terraform)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "All"
    payloads            = file("${path.module}/support_files/macos_configuration_profiles/security_and_privacy_laptops.mobileconfig")
    category_id         = jamfplatform_pro_category.common["global"].id
  }
  scope = {
    targets = {
      computer_group_ids = [
        jamfplatform_device_group.computers_model["laptops"].jamf_pro_id
      ]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "security_and_privacy_desktops" {
  general = {
    name                = "Security and Privacy - Desktops (Managed by Terraform)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "All"
    payloads            = file("${path.module}/support_files/macos_configuration_profiles/security_and_privacy_desktops.mobileconfig")
    category_id         = jamfplatform_pro_category.common["global"].id
  }
  scope = {
    targets = {
      computer_group_ids = [
        jamfplatform_device_group.computers_model["desktops"].jamf_pro_id
      ]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "sso_extension_entra_id" {
  general = {
    name                = "Single Sign-On Extension - Entra ID (Managed by Terraform)"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "All"
    payloads            = file("${path.module}/support_files/macos_configuration_profiles/sso_extension_entra_id.mobileconfig")
    category_id         = jamfplatform_pro_category.common["global"].id
  }
  scope = {
    targets = {
      all_computers = true
      all_jss_users = false
    }
  }
}
