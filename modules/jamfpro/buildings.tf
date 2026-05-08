# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Buildings_and_Departments.html
#
# The locals map drives a single resource block via for_each, creating one
# building per entry. Add or remove map entries to add or remove buildings —
# Terraform handles the creates and deletes on the next apply. The map key
# (e.g. "north") becomes the resource address in state and can be referenced
# elsewhere as jamfpro_building.common["north"].id.

locals {
  buildings = {
    north = "North Wing (Managed by Terraform)",
    south = "South Wing (Managed by Terraform)",
    east  = "East Wing (Managed by Terraform)",
    west  = "West Wing (Managed by Terraform)",
  }
}

resource "jamfpro_building" "common" {
  for_each = local.buildings
  name     = each.value
}
