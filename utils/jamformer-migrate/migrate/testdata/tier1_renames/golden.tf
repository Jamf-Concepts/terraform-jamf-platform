resource "jamfplatform_pro_category" "apps" {
  name     = "Applications"
  priority = 9
}

resource "jamfplatform_pro_department" "engineering" {
  name = "Engineering"
}

resource "jamfplatform_pro_site" "hq" {
  name = "HQ"
}

resource "jamfplatform_pro_dock_item" "safari" {
  name     = "Safari"
  type     = "App"
  path     = "file:///Applications/Safari.app"
  contents = ""
}

resource "jamfplatform_pro_api_role" "readonly" {
  display_name = "Read-Only Role"
  privileges   = ["Read Computers", "Read Mobile Devices"]
}

resource "jamfplatform_pro_access_management_settings" "main" {
  institution_name = "Acme Corp"
}
