## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "jamf/jamfplatform"
      version               = ">= 1.5.0" # jamfplatform_apple_app_store_app data source
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

locals {
  # for_each needs a stable, unique key per app; the URL itself is unique
  # across the selected set and doubles as that key.
  app_store_urls             = toset(var.app_store_urls)
  vpp_license_available_urls = toset(var.vpp_license_available_urls)
}

## Resolve each selected App Store URL into name/version/bundle_id/icon --
## Foundations only collects the URL itself, nothing else.
data "jamfplatform_apple_app_store_app" "mobile" {
  for_each  = local.app_store_urls
  store_url = each.value
  target    = "mobile_device"
}

resource "jamfplatform_pro_icon" "mobile" {
  # icon_url is null for a listing with no icon -- only create an icon
  # resource for apps that actually have one.
  for_each = {
    for key, app in data.jamfplatform_apple_app_store_app.mobile : key => app
    if app.icon_url != null
  }

  icon_file_source = each.value.icon_url
}

resource "jamfplatform_pro_mobile_device_app" "mobile" {
  for_each = data.jamfplatform_apple_app_store_app.mobile

  general = {
    name                  = each.value.name
    version               = each.value.version
    bundle_id             = each.value.bundle_id
    itunes_store_url      = each.value.url
    itunes_country_region = each.value.country_region
    is_free               = each.value.is_free
    deploy_automatically  = false
  }

  scope = {
    targets = {
      all_mobile_devices = true
    }
  }

  self_service = {
    self_service_description = each.value.description
    self_service_icon = each.value.icon_url != null ? {
      id = jamfplatform_pro_icon.mobile[each.key].id
    } : null
  }

  # assign_vpp_device_based_licenses is rejected outright for a title that
  # isn't actually VPP-backed, or one this environment has no unassigned
  # license for (409 "App is not available for device assignment") -- only
  # ever set it when both are true.
  vpp = (each.value.vpp_device_based_licensing && contains(local.vpp_license_available_urls, each.key)) ? {
    assign_vpp_device_based_licenses = true
  } : null

  # Each App Store release bumps `version`; ignore it so routine app updates
  # don't show as a pending Terraform change on every plan.
  lifecycle {
    ignore_changes = [general.version]
  }
}
