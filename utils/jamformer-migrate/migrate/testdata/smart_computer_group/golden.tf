resource "jamfplatform_device_group" "macos_ventura" {
  name = "macOS Ventura+"


  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than or equal"
      value    = "13.0"
    },
    {
      and_or                  = "or"
      has_opening_parenthesis = true
      criteria                = "Serial Number"
      operator                = "is"
      value                   = "ABC123"
      has_closing_parenthesis = true
    },
  ]
}

resource "jamfplatform_device_group" "test_machines" {
  name        = "Test Machines"
  members     = ["42", "43", "44"]
  group_type  = "static"
  device_type = "computer"
}

# Reference to a group in another resource
resource "jamfplatform_pro_macos_configuration_profile" "example" {

  general = {
    name                = "Example Profile"
    level               = "Computer"
    distribution_method = "Install Automatically"
    payloads            = "<plist/>"
    category_id         = 1
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.macos_ventura.jamf_pro_id]
    }
  }
}
