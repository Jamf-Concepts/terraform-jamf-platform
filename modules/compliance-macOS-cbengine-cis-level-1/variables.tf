variable "jamfplatform_base_url" {
  description = "Jamf Platform API gateway URL."
  type        = string
}

variable "jamfplatform_client_id" {
  description = "Jamf Platform Client ID for authentication."
  type        = string
}

variable "jamfplatform_client_secret" {
  description = "Jamf Platform Client Secret for authentication."
  type        = string
  sensitive   = true
}
