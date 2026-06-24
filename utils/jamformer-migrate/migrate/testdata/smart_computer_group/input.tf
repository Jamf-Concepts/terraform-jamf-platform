resource "jamfpro_smart_computer_group" "macos_ventura" {
  name = "macOS Ventura+"

  criteria {
    name          = "Operating System Version"
    priority      = 0
    and_or        = "and"
    search_type   = "greater than or equal"
    value         = "13.0"
    opening_paren = false
    closing_paren = false
  }

  criteria {
    name          = "Serial Number"
    priority      = 1
    and_or        = "or"
    search_type   = "is"
    value         = "ABC123"
    opening_paren = true
    closing_paren = true
  }
}

resource "jamfpro_static_computer_group" "test_machines" {
  name    = "Test Machines"
  members = ["42", "43", "44"]
}

# Reference to a group in another resource
resource "jamfpro_macos_configuration_profile_plist" "example" {
  name             = "Example Profile"
  level            = "Computer"
  distribution_method = "Install Automatically"
  payloads         = "<plist/>"
  category_id      = 1

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.macos_ventura.id]
  }
}
