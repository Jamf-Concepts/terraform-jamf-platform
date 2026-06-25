# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Buildings_and_Departments.html
#
# Departments used for scoping mobile device apps and user assignments.
# Referenced elsewhere as jamfplatform_pro_department.common["hr"].id etc.

locals {
  departments = {
    hr          = "HR (Managed by Terraform)",
    engineering = "Engineering (Managed by Terraform)",
    sales       = "Sales (Managed by Terraform)",
    marketing   = "Marketing (Managed by Terraform)",
  }
}

resource "jamfplatform_pro_department" "common" {
  for_each = local.departments
  name     = each.value
}
