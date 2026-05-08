# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Categories.html
#
# Categories are referenced throughout the module by their map key, e.g.
# jamfpro_category.common["applications"].id. Add a new entry here before
# using it in another resource.

locals {
  category_names = {
    global       = "Global (Managed by Terraform)",
    applications = "Applications (Managed by Terraform)",
    scripts      = "Scripts (Managed by Terraform)"
  }
}

resource "jamfpro_category" "common" {
  for_each = local.category_names
  name     = each.value
}
