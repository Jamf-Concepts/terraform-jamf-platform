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

variable "include_google_chrome" {
  description = "Whether to include the Google Chrome App Installer (if true, it is created using the management-app-installers module instead)"
  type        = bool
  default     = false
}

variable "google_chrome_cloud_management_enrollment_token" {
  description = "The enrollment token for Google Chrome Cloud Management"
  type        = string
  sensitive   = true
}

variable "app_installers" {
  description = "Set of selected App Installers"
  type        = list(string)
  default     = []
}
