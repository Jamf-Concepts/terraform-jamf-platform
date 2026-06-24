resource "jamfplatform_pro_advanced_computer_search" "lab_macs" {
  name = "Lab Macs running Sequoia"



  display_fields = ["Computer Name", "Serial Number", "Last Inventory Update"]
  criteria = [
    {
      name                    = "Computer Name"
      search_type             = "like"
      value                   = "lab"
      has_opening_parenthesis = true
    },
    {
      name                    = "Operating System Version"
      search_type             = "greater than or equal"
      value                   = "15.0"
      and_or                  = "and"
      has_closing_parenthesis = true
    },
  ]
}
