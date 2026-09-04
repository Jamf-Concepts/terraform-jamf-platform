variable "jamfplatform_base_url" {
  type        = string
  description = "Jamf Platform API gateway URL, e.g. https://us.api.jamfcloud.com"
}

variable "jamfplatform_client_id" {
  type      = string
  sensitive = true
}

variable "jamfplatform_client_secret" {
  type      = string
  sensitive = true
}

variable "jamfplatform_environment_id" {
  type        = string
  description = "Your Jamf platform environment UUID"
  sensitive   = true
}
