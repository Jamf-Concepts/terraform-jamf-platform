variable "jamfplatform_base_url" {
  type        = string
  description = "Jamf Platform API gateway URL. US: https://us.api.jamfcloud.com, EU: https://eu.api.jamfcloud.com, APAC: https://apac.api.jamfcloud.com"
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
  description = "Platform environment UUID. The Integration details panel at account.jamf.com shows it."
}
