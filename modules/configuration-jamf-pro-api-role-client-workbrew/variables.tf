## Define miscellaneous variables
variable "jamfpro_instance_url" {
  description = "Jamf Pro Instance name."
  type        = string
}

variable "jamfpro_auth_method" {
  description = "Jamf Pro Auth Method."
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
