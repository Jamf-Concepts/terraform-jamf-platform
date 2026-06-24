resource "jamfplatform_pro_computer_extension_attribute" "popup_menu" {
  name               = "tf-ghatest-cexa-popup-menu-example"
  enabled            = true
  description        = "An attribute collected from a pop-up menu."
  input_type         = "POPUP"
  popup_menu_choices = ["Option 1", "Option 2", "Option 3"]
  data_type          = "STRING"
  inventory_display  = "USER_AND_LOCATION"
}

resource "jamfplatform_pro_computer_extension_attribute" "script_ea" {
  name              = "tf-example-cexa-hello-world"
  enabled           = true
  description       = "An attribute collected via a script."
  input_type        = "SCRIPT"
  data_type         = "STRING"
  inventory_display = "GENERAL"
  script            = "#!/bin/bash\necho 'Hello, World!!!!! :)'"
}
