variable "jamfpro_instance_url" {
  type      = string
  sensitive = true
  default   = ""
}

variable "radar_user" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jsc_username" {
  type      = string
  sensitive = false
  default   = ""
}

variable "jsc_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "tje_okta_clientid" {
  type      = string
  sensitive = true
  default   = ""
}

variable "tje_okta_orgdomain" {
  type      = string
  sensitive = true
  default   = ""
}

variable "clientid" {
  type      = string
  sensitive = true
  default   = ""
}

variable "clientsecret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfpro_instance_fqdn" {
  type      = string
  sensitive = true
  default   = ""
}

variable "auth_method" {
  type      = string
  sensitive = true
  default   = ""
}

variable "basic_auth_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "basic_auth_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfpro_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfpro_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "access_policy_name" {
  type    = string
  default = ""
}

variable "vpn_route" {
  type    = string
  default = "Nearest Data Center"
}

variable "routing_type" {
  type    = string
  default = "CUSTOM" # DIRECT or CUSTOM
}

variable "routing_dns_type" {
  type    = string
  default = "IPv6" # IPv4 or IPv6
}

variable "category_name" {
  type    = string
  default = "Business & Industry"
  # OPTIONS: Adult, Advertising, App Counters, App Stores, Audio & Music, Browsers, Business & Industry, Cloud & File Storage, Communication, Content Servers, Custom, Entertainment, Extreme, Finance, Gambling, Games, Generative AI, Illegal, Lifestyle, Medical, Navigation, News & Sport, OS Updates, Productivity, Reference, Shopping, Social, Technology, Travel, Uncategorized, Video & Photo
}

variable "risk_control_enabled" {
  type    = bool
  default = true
}

variable "risk_threshold" {
  type    = string
  default = "HIGH" # Risk level threshold (when enabled), options of HIGH, MEDIUM, LOW
}

variable "risk_threshold_notifications" {
  type    = bool
  default = true
}

variable "security_doh_block" {
  type    = bool
  default = true
}

variable "security_doh_block_notifications" {
  type    = bool
  default = true
}

variable "security_management_block" {
  type    = bool
  default = true
}

variable "security_management_block_notification" {
  type    = bool
  default = true
}

variable "all_users" {
  type    = bool
  default = true
}

variable "block_page_logo" {
  type      = string
  sensitive = false
  default   = ""
}

variable "support_files_path_prefix" {
  type    = string
  default = ""
}

variable "enable_jsc_uemc" {
  type    = string
  default = ""
}

variable "enable_jsc_uemc_output" {
  type    = string
  default = ""
}

variable "random_string" {
  type    = string
  default = ""
}

variable "entropy_string" {
  type    = string
  default = ""
}
