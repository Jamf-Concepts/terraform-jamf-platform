resource "jamfpro_computer_extension_attribute" "popup_menu" {
  name                   = "tf-ghatest-cexa-popup-menu-example"
  enabled                = true
  description            = "An attribute collected from a pop-up menu."
  input_type             = "POPUP"
  popup_menu_choices     = ["Option 1", "Option 2", "Option 3"]
  inventory_display_type = "USER_AND_LOCATION"
  data_type              = "STRING"
}

resource "jamfpro_computer_extension_attribute" "script_ea" {
  name                   = "tf-example-cexa-hello-world"
  enabled                = true
  description            = "An attribute collected via a script."
  input_type             = "SCRIPT"
  script_contents        = "#!/bin/bash\necho 'Hello, World!!!!! :)'"
  inventory_display_type = "GENERAL"
  data_type              = "STRING"
}
