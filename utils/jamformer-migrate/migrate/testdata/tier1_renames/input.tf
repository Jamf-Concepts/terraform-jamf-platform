resource "jamfpro_category" "apps" {
  name     = "Applications"
  priority = 9
}

resource "jamfpro_department" "engineering" {
  name = "Engineering"
}

resource "jamfpro_site" "hq" {
  name = "HQ"
}

resource "jamfpro_dock_item" "safari" {
  name     = "Safari"
  type     = "App"
  path     = "file:///Applications/Safari.app"
  contents = ""
}

resource "jamfpro_api_role" "readonly" {
  display_name = "Read-Only Role"
  privileges   = ["Read Computers", "Read Mobile Devices"]
}

resource "jamfpro_access_management_settings" "main" {
  institution_name = "Acme Corp"
}
