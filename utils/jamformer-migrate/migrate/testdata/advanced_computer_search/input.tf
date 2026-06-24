resource "jamfpro_advanced_computer_search" "lab_macs" {
  name    = "Lab Macs running Sequoia"
  view_as = "Standard Web Page"
  sort1   = "Serial Number"
  sort2   = "Username"
  sort3   = "Department"

  criteria {
    name          = "Computer Name"
    priority      = 0
    and_or        = "and"
    search_type   = "like"
    value         = "lab"
    opening_paren = true
    closing_paren = false
  }

  criteria {
    name          = "Operating System Version"
    priority      = 1
    and_or        = "and"
    search_type   = "greater than or equal"
    value         = "15.0"
    opening_paren = false
    closing_paren = true
  }

  display_fields = ["Computer Name", "Serial Number", "Last Inventory Update"]
}
