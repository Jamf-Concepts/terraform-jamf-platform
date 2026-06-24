resource "jamfpro_mobile_device_extension_attribute" "popup_menu" {
  name                   = "Device Location"
  description            = "The primary location where this device is used"
  data_type              = "STRING"
  inventory_display_type = "USER_AND_LOCATION"
  input_type             = "POPUP"
  popup_menu_choices = [
    "Head Office",
    "Branch Office",
    "Home Office",
    "Client Site"
  ]
}

resource "jamfpro_mobile_device_extension_attribute" "text_field" {
  name                   = "User Department"
  description            = "The department to which the device user belongs"
  data_type              = "STRING"
  inventory_display_type = "GENERAL"
  input_type             = "TEXT"
}
