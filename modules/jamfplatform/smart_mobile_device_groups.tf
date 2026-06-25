# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Smart_Groups.html
#
# Model-based groups used to scope mobile device profiles.
# all_managed has no criteria, which Jamf Pro treats as matching all managed
# mobile devices.

locals {
  mobile_device_models = {
    iphones = {
      name  = "Model - iPhones (Managed by Terraform)"
      model = "iPhone"
    }
    ipads = {
      name  = "Model - iPads (Managed by Terraform)"
      model = "iPad"
    }
  }
}


resource "jamfplatform_device_group" "mobile_model" {
  for_each    = local.mobile_device_models
  name        = each.value.name
  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Model"
      operator = "like"
      value    = each.value.model
    }
  ]
}

resource "jamfplatform_device_group" "mobile_all_managed" {
  name        = "All Managed (Managed by Terraform)"
  group_type  = "smart"
  device_type = "mobile"
  criteria    = []
}
