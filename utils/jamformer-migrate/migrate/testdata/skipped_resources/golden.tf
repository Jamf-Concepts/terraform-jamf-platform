resource "jamfpro_engage_settings" "engage" {
  enabled = true
}

resource "jamfpro_managed_software_update_feature_toggle" "msut" {
  enabled = true
}

resource "jamfplatform_pro_category" "example" {
  name     = "Example"
  priority = 9
}
