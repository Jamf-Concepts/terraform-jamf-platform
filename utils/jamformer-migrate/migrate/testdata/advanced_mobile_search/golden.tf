resource "jamfplatform_pro_advanced_mobile_device_search" "all_iphones" {
  name = "All iPhones"


  display_fields = ["Device Name", "Serial Number"]
  criteria = [
    {
      name        = "Model"
      search_type = "like"
      value       = "iPhone"
    },
  ]
}
