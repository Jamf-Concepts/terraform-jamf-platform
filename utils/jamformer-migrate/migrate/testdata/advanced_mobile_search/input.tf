resource "jamfpro_advanced_mobile_device_search" "all_iphones" {
  name    = "All iPhones"
  view_as = "Standard Web Page"
  sort1   = "Serial Number"

  criteria {
    name          = "Model"
    priority      = 0
    and_or        = "and"
    search_type   = "like"
    value         = "iPhone"
    opening_paren = false
    closing_paren = false
  }

  display_fields = ["Device Name", "Serial Number"]
}
