variable "jamfplatform_base_url" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jsc_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jsc_password" {
  type      = string
  sensitive = true
  default   = ""
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


