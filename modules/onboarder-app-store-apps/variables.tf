variable "app_store_urls" {
  description = "App Store URLs for mobile device apps to create, e.g. https://apps.apple.com/us/app/slack/id618783545. Each is resolved into name/version/bundle_id/icon via the App Store listing and deployed as a Mobile Device App, made available in Self Service to all mobile devices."
  type        = list(string)
  default     = []
}

variable "vpp_license_available_urls" {
  description = "Subset of app_store_urls that the caller has confirmed already have an unassigned Volume Purchasing license in this environment. Only these get `vpp.assign_vpp_device_based_licenses` set -- Apple requires buying/claiming VPP content by hand in Apps and Books, so assigning a license this environment doesn't have fails the whole apply with a 409. Apps not in this set are still created, just without automatic VPP assignment."
  type        = list(string)
  default     = []
}
