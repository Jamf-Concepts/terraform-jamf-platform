resource "jamfplatform_pro_mobile_device_extension_attribute" "popup_menu" {
  name        = "Device Location"
  description = "The primary location where this device is used"
  data_type   = "STRING"
  input_type  = "POPUP"
  popup_menu_choices = [
    "Head Office",
    "Branch Office",
    "Home Office",
    "Client Site"
  ]
  inventory_display = "USER_AND_LOCATION"
}

resource "jamfplatform_pro_mobile_device_extension_attribute" "text_field" {
  name              = "User Department"
  description       = "The department to which the device user belongs"
  data_type         = "STRING"
  input_type        = "TEXT"
  inventory_display = "GENERAL"
}
