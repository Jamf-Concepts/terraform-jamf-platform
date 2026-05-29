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


resource "jamfpro_smart_mobile_device_group_v1" "model" {
  for_each = local.mobile_device_models
  name     = each.value.name
  criteria {
    name        = "Model"
    priority    = 0
    search_type = "like"
    value       = each.value.model
  }
}

resource "jamfpro_smart_mobile_device_group_v1" "all_managed" {
  name = "All Managed (Managed by Terraform)"
}
