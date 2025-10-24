variable "jamfpro_instance_url" {
  description = "Jamf Pro URL name."
  type        = string
  default     = ""
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

variable "jamfprotect_url" {
  description = "Jamf Protect URL name."
  type        = string
  default     = ""
}

variable "jamfprotect_client_id" {
  description = "Jamf Protect Client ID for authentication."
  type        = string
  default     = ""
}

variable "jamfprotect_client_password" {
  description = "Jamf Protect Client passwrd for authentication."
  type        = string
  sensitive   = true
  default     = ""
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

variable "organization_name" {
  type    = string
  default = ""
}

variable "jamf_pro_activation_code" {
  type    = string
  default = ""
}
