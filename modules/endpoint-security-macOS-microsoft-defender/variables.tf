## Define miscellaneous variables
variable "jamfplatform_base_url" {
  description = "Jamf Pro Instance name."
  type        = string
  default     = ""
}

variable "jamfplatform_client_id" {
  description = "Jamf Pro Client ID for authentication."
  type        = string
  default     = ""
}

variable "jamfplatform_client_secret" {
  description = "Jamf Pro Client Secret for authentication."
  type        = string
  sensitive   = true
  default     = ""
}

variable "random_string" {
  type    = string
  default = ""
}

variable "defender_onboarding_plist_path" {
  description = "Path to the Microsoft Defender ATP onboarding plist file"
  type        = string
  default     = ""
}

variable "defender_onboarding_plist" {
  description = "Base64-encoded Microsoft Defender ATP onboarding plist content"
  type        = string
  default     = ""
}
