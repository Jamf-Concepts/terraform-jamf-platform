variable "jamfpro_instance_url" {
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

variable "jamfpro_auth_method" {
  description = "Jamf Pro Auth Method."
  type        = string
  default     = "oauth2" #basic or oauth2
}

variable "jamfpro_client_id" {
  description = "Jamf Pro Client ID for authentication."
  type        = string
  default     = ""
}

variable "jamfpro_client_secret" {
  description = "Jamf Pro Client Secret for authentication."
  type        = string
  sensitive   = true
  default     = ""
}

variable "random_string" {
  type    = string
  default = ""
}

variable "entropy_string" {
  type    = string
  default = ""
}
