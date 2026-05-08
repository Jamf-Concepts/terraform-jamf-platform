# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Apps_Purchased_in_Volume.html
#
# App metadata (name, version, bundle ID, icon URL) is fetched live from the
# iTunes Search API using the itunessearchapi provider — no manual version
# pinning needed.
#
# VPP licence check: vpp_adam_ids reads the content list from the VPP location
# (populated after the async sync in volume_purchasing_locations.tf — see that
# file for the time_sleep pattern). For each app, if its Adam ID is in the list
# the resource assigns a device-based VPP licence; otherwise it falls back to
# a free install. Apps without licences still appear in Self Service.

locals {
  apple_app_store_urls = {
    keynote    = "https://apps.apple.com/gb/app/keynote-design-presentations/id361285480",
    numbers    = "https://apps.apple.com/gb/app/numbers-make-spreadsheets/id361304891",
    pages      = "https://apps.apple.com/gb/app/pages-create-documents/id361309726",
    garageband = "https://apps.apple.com/gb/app/garageband/id682658836?mt=12",
    imovie     = "https://apps.apple.com/gb/app/imovie/id408981434?mt=12"
  }
  apple_app_vpp_status = {
    for result in data.itunessearchapi_content.apple_apps.results : result.track_id => {
      has_licenses         = contains(local.vpp_adam_ids, tostring(result.track_id))
      vpp_admin_account_id = contains(local.vpp_adam_ids, tostring(result.track_id)) ? data.jamfpro_volume_purchasing_locations.default.id : -1
    }
  }
  vpp_adam_ids = [
    for content in data.jamfpro_volume_purchasing_locations.default.content :
    content.adam_id
  ]
}

data "itunessearchapi_content" "apple_apps" {
  app_store_urls = values(local.apple_app_store_urls)
}

resource "jamfpro_icon" "apple_app" {
  for_each = {
    for idx, result in data.itunessearchapi_content.apple_apps.results : result.track_id => result
    if result.artwork_url != null
  }
  icon_file_web_source = each.value.artwork_url
}

resource "jamfpro_mac_application" "apple_app" {
  for_each = {
    for idx, result in data.itunessearchapi_content.apple_apps.results : result.track_id => result
    if result.track_name != null
  }
  name            = "${each.value.track_name} (Managed by Terraform)"
  version         = each.value.version
  bundle_id       = each.value.bundle_id
  url             = each.value.track_view_url
  category_id     = jamfpro_category.common["applications"].id
  deployment_type = "Make Available in Self Service"
  is_free         = true
  scope {
    all_computers = false
    all_jss_users = false
    building_ids = [
      jamfpro_building.common["north"].id,
      jamfpro_building.common["south"].id
    ]
  }
  self_service {
    install_button_text             = "Install"
    self_service_description        = each.value.description
    force_users_to_view_description = false
    feature_on_main_page            = true
    notification                    = "Self Service"
    self_service_icon {
      id = jamfpro_icon.apple_app[each.key].id
    }
  }
  vpp {
    assign_vpp_device_based_licenses = local.apple_app_vpp_status[each.key].has_licenses
    vpp_admin_account_id             = local.apple_app_vpp_status[each.key].vpp_admin_account_id
  }
}

