## Define miscellaneous variables
variable "jamfpro_instance_url" {
  description = "Jamf Pro Instance name."
  type        = string
}

variable "jamfpro_auth_method" {
  description = "Jamf Pro Auth Method."
  type        = string
  default     = "oauth2" #basic or oauth2
}

variable "jamfpro_client_id" {
  description = "Jamf Pro Client ID for authentication."
  type        = string
}

variable "jamfpro_client_secret" {
  description = "Jamf Pro Client Secret for authentication."
  type        = string
  sensitive   = true
}

variable "sentinelone_org_token" {
  description = "SentinelOne organization/site token used to register the agent"
  type        = string
  sensitive   = true
}

variable "sentinelone_pkg_filename" {
  description = "Display name for the package in Jamf Pro. Auto-derived from path if using sentinelone_pkg_path."
  type        = string
  default     = "SentinelOne.pkg"
}

variable "sentinelone_pkg_path" {
  description = "Local file path to the SentinelOne .pkg installer"
  type        = string
  default     = ""
}

variable "sentinelone_pkg_base64" {
  description = "Base64-encoded SentinelOne .pkg installer content"
  type        = string
  default     = ""
}

variable "sentinelone_pkg_url" {
  description = "HTTPS URL to the SentinelOne .pkg in S3 (downloaded at apply time via aws s3 cp)"
  type        = string
  default     = ""
}
