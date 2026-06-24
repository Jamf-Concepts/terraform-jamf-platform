resource "jamfplatform_pro_enrollment_customization" "welcome" {
  display_name = "Corporate Enrollment"
  description  = "Default enrollment experience"



  icon_source = "/path/to/logo.png"
  branding_settings = {
    button_color      = "0066CC"
    button_text_color = "FFFFFF"
    background_color  = "F5F5F5"
    body_text_color   = "000000"
  }
  text_panes = [
    {
      display_name         = "Welcome Message"
      rank                 = 1
      title                = "Welcome to Our Company"
      body                 = "We're excited to get your device set up."
      previous_button_text = "Back"
      next_button_text     = "Continue"
    },
  ]
  sso_panes = [
    {
      display_name                       = "Corporate SSO"
      rank                               = 2
      is_group_enrollment_access_enabled = true
      group_enrollment_access_name       = "All-Employees"
      pass_user_info_to_jamf_connect     = true
    },
  ]
}
