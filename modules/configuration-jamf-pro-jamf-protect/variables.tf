variable "jamfpro_instance_url" {
  description = "Jamf Pro URL name."
  type        = string
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

variable "jamfprotect_url" {
  description = "Jamf Protect URL name."
  type        = string
}

variable "jamfprotect_clientID" {
  description = "Jamf Protect Client ID for authentication."
  type        = string
}

variable "jamfprotect_client_password" {
  description = "Jamf Protect Client passwrd for authentication."
  type        = string
  sensitive   = true
}

variable "jamfpro_auth_method" {
  description = "Jamf Pro Auth Method."
  type        = string
  default     = "oauth2" #basic or oauth2
}

variable "random_string" {
  type    = string
  default = ""
}

variable "entropy_string" {
  type    = string
  default = ""
}
