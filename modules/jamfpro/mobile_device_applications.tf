# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Apps_Purchased_in_Volume.html
#
# App metadata is fetched from the iTunes Search API at plan time. See
# mac_applications.tf for the VPP licence check pattern and
# volume_purchasing_locations.tf for the async sync dependency.
#
# Three groups of apps are managed here:
#   apple_app         - Apple first-party apps, scoped to Marketing, Self Service
#   jamf_self_service - Jamf Self Service for iOS, pushed to all devices
#                       automatically, removed when MDM profile is removed
#   microsoft_office  - Microsoft 365 iOS apps, scoped to all mobile devices,
#                       Self Service

locals {
  ios_apple_app_store_urls = {
    keynote    = "https://apps.apple.com/gb/app/keynote/id361285480",
    numbers    = "https://apps.apple.com/gb/app/numbers/id361304891",
    pages      = "https://apps.apple.com/gb/app/pages/id361309726",
    garageband = "https://apps.apple.com/gb/app/garageband/id408709785",
    imovie     = "https://apps.apple.com/gb/app/imovie/id377298193"
  }
  ios_apple_app_vpp_status = {
    for result in data.itunessearchapi_content.ios_apple_apps.results : result.track_id => {
      has_licenses         = contains(local.vpp_adam_ids, tostring(result.track_id))
      vpp_admin_account_id = contains(local.vpp_adam_ids, tostring(result.track_id)) ? data.jamfpro_volume_purchasing_locations.default.id : -1
    }
  }
  ios_jamf_self_service_app_store_url = "https://apps.apple.com/gb/app/jamf-self-service/id718509958"
  ios_jamf_self_service_vpp_status = {
    for result in data.itunessearchapi_content.ios_jamf_self_service.results : result.track_id => {
      has_licenses         = contains(local.vpp_adam_ids, tostring(result.track_id))
      vpp_admin_account_id = contains(local.vpp_adam_ids, tostring(result.track_id)) ? data.jamfpro_volume_purchasing_locations.default.id : -1
    }
  }
  ios_microsoft_office_app_store_urls = {
    excel      = "https://apps.apple.com/gb/app/microsoft-excel/id586683407",
    powerpoint = "https://apps.apple.com/gb/app/microsoft-powerpoint/id586449534",
    word       = "https://apps.apple.com/gb/app/microsoft-word/id586447913",
    outlook    = "https://apps.apple.com/gb/app/microsoft-outlook/id951937596",
    teams      = "https://apps.apple.com/gb/app/microsoft-teams/id1113153706"
  }
  ios_microsoft_office_vpp_status = {
    for result in data.itunessearchapi_content.ios_microsoft_office_apps.results : result.track_id => {
      has_licenses         = contains(local.vpp_adam_ids, tostring(result.track_id))
      vpp_admin_account_id = contains(local.vpp_adam_ids, tostring(result.track_id)) ? data.jamfpro_volume_purchasing_locations.default.id : -1
    }
  }
}

data "itunessearchapi_content" "ios_apple_apps" {
  app_store_urls = values(local.ios_apple_app_store_urls)
}

data "itunessearchapi_content" "ios_jamf_self_service" {
  app_store_urls = [local.ios_jamf_self_service_app_store_url]
}

data "itunessearchapi_content" "ios_microsoft_office_apps" {
  app_store_urls = values(local.ios_microsoft_office_app_store_urls)
}

resource "jamfpro_icon" "ios_apple_app" {
  for_each = {
    for idx, result in data.itunessearchapi_content.ios_apple_apps.results : result.track_id => result
    if result.artwork_url != null
  }
  icon_file_web_source = each.value.artwork_url
}

resource "jamfpro_icon" "ios_jamf_self_service" {
  for_each = {
    for idx, result in data.itunessearchapi_content.ios_jamf_self_service.results : result.track_id => result
    if result.artwork_url != null
  }
  icon_file_web_source = each.value.artwork_url
}

resource "jamfpro_icon" "ios_microsoft_office" {
  for_each = {
    for idx, result in data.itunessearchapi_content.ios_microsoft_office_apps.results : result.track_id => result
    if result.artwork_url != null
  }
  icon_file_web_source = each.value.artwork_url
}

resource "jamfpro_mobile_device_application" "apple_app" {
  for_each = {
    for idx, result in data.itunessearchapi_content.ios_apple_apps.results : result.track_id => result
    if result.track_name != null
  }
  name                                   = "${each.value.track_name} (Managed by Terraform)"
  display_name                           = "${each.value.track_name} (Managed by Terraform)"
  bundle_id                              = each.value.bundle_id
  version                                = each.value.version
  internal_app                           = false
  category_id                            = jamfpro_category.common["applications"].id
  site_id                                = -1
  itunes_store_url                       = each.value.track_view_url
  external_url                           = each.value.track_view_url
  itunes_country_region                  = "US"
  itunes_sync_time                       = 0
  deploy_automatically                   = false
  deploy_as_managed_app                  = true
  remove_app_when_mdm_profile_is_removed = false
  prevent_backup_of_app_data             = false
  allow_user_to_delete                   = true
  require_network_tethered               = false
  keep_description_and_icon_up_to_date   = false
  keep_app_updated_on_devices            = false
  free                                   = true
  take_over_management                   = true
  host_externally                        = true
  make_available_after_install           = true
  self_service {
    self_service_description = each.value.description
    feature_on_main_page     = true
    notification             = false
    self_service_icon {
      id = jamfpro_icon.ios_apple_app[each.key].id
    }
  }
  vpp {
    assign_vpp_device_based_licenses = local.ios_apple_app_vpp_status[each.key].has_licenses
    vpp_admin_account_id             = local.ios_apple_app_vpp_status[each.key].vpp_admin_account_id
  }
  scope {
    all_mobile_devices = false
    all_jss_users      = false
    department_ids = [
      jamfpro_department.department["marketing"].id
    ]
  }
}

resource "jamfpro_mobile_device_application" "jamf_self_service" {
  for_each = {
    for idx, result in data.itunessearchapi_content.ios_jamf_self_service.results : result.track_id => result
  }
  name                                   = "${each.value.track_name} (Managed by Terraform)"
  display_name                           = "${each.value.track_name} (Managed by Terraform)"
  bundle_id                              = each.value.bundle_id
  version                                = each.value.version
  internal_app                           = false
  category_id                            = jamfpro_category.common["applications"].id
  site_id                                = -1
  itunes_store_url                       = each.value.track_view_url
  external_url                           = each.value.track_view_url
  itunes_country_region                  = "US"
  itunes_sync_time                       = 0
  deploy_automatically                   = true
  deploy_as_managed_app                  = true
  remove_app_when_mdm_profile_is_removed = true
  prevent_backup_of_app_data             = false
  allow_user_to_delete                   = false
  require_network_tethered               = false
  keep_description_and_icon_up_to_date   = false
  keep_app_updated_on_devices            = false
  free                                   = true
  take_over_management                   = true
  host_externally                        = true
  make_available_after_install           = false
  self_service {
    self_service_description = each.value.description
    feature_on_main_page     = false
    notification             = false
    self_service_icon {
      id = jamfpro_icon.ios_jamf_self_service[each.key].id
    }
  }
  vpp {
    assign_vpp_device_based_licenses = local.ios_jamf_self_service_vpp_status[each.key].has_licenses
    vpp_admin_account_id             = local.ios_jamf_self_service_vpp_status[each.key].vpp_admin_account_id
  }
  app_configuration {
    preferences = file("${path.module}/support_files/app_configurations/appconfig_jamf_self_service.xml")
  }
  scope {
    all_mobile_devices = true
    all_jss_users      = false
  }
}

resource "jamfpro_mobile_device_application" "microsoft_office" {
  for_each = {
    for idx, result in data.itunessearchapi_content.ios_microsoft_office_apps.results : result.track_id => result
    if result.track_name != null
  }
  name                                   = "${each.value.track_name} (Managed by Terraform)"
  display_name                           = "${each.value.track_name} (Managed by Terraform)"
  bundle_id                              = each.value.bundle_id
  version                                = each.value.version
  internal_app                           = false
  category_id                            = jamfpro_category.common["applications"].id
  site_id                                = -1
  itunes_store_url                       = each.value.track_view_url
  external_url                           = each.value.track_view_url
  itunes_country_region                  = "US"
  itunes_sync_time                       = 0
  deploy_automatically                   = false
  deploy_as_managed_app                  = true
  remove_app_when_mdm_profile_is_removed = false
  prevent_backup_of_app_data             = false
  allow_user_to_delete                   = true
  require_network_tethered               = false
  keep_description_and_icon_up_to_date   = false
  keep_app_updated_on_devices            = false
  free                                   = true
  take_over_management                   = true
  host_externally                        = true
  make_available_after_install           = true
  self_service {
    self_service_description = each.value.description
    feature_on_main_page     = true
    notification             = false
    self_service_icon {
      id = jamfpro_icon.ios_microsoft_office[each.key].id
    }
  }
  vpp {
    assign_vpp_device_based_licenses = local.ios_microsoft_office_vpp_status[each.key].has_licenses
    vpp_admin_account_id             = local.ios_microsoft_office_vpp_status[each.key].vpp_admin_account_id
  }
  scope {
    all_mobile_devices = true
    all_jss_users      = false
  }
}
