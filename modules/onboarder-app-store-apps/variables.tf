variable "app_store_urls" {
  description = "App Store URLs for mobile device apps to create, e.g. https://apps.apple.com/us/app/slack/id618783545. Each is resolved into name/version/bundle_id/icon via the App Store listing and deployed as a Mobile Device App, made available in Self Service to all mobile devices."
  type        = list(string)
  default     = []
}
