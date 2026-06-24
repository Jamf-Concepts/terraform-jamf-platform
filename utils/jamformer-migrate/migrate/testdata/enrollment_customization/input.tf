resource "jamfpro_enrollment_customization" "welcome" {
  site_id                               = "-1"
  display_name                          = "Corporate Enrollment"
  description                           = "Default enrollment experience"
  enrollment_customization_image_source = "/path/to/logo.png"

  branding_settings {
    text_color        = "000000"
    button_color      = "0066CC"
    button_text_color = "FFFFFF"
    background_color  = "F5F5F5"
  }

  text_pane {
    display_name         = "Welcome Message"
    rank                 = 1
    title                = "Welcome to Our Company"
    body                 = "We're excited to get your device set up."
    back_button_text     = "Back"
    continue_button_text = "Continue"
  }

  sso_pane {
    display_name                       = "Corporate SSO"
    rank                               = 2
    is_group_enrollment_access_enabled = true
    group_enrollment_access_name       = "All-Employees"
    is_use_jamf_connect                = true
  }
}
