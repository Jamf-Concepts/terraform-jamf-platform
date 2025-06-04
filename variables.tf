## Define Jamf Pro provider variables (populated by .tfvars file)
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

variable "jamfpro_username" {
  description = "Jamf Pro username used for authentication."
  type        = string
  default     = ""
}

variable "jamfpro_password" {
  description = "Jamf Pro password used for authentication."
  type        = string
  sensitive   = true
  default     = ""
}

variable "jamfprotect_url" {
  description = "Jamf Protect URL name."
  type        = string
  default     = ""
}

variable "jamfprotect_clientid" {
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

## Define JSC provider variables (populated by .tfvars file)
variable "jsc_username" {
  type      = string
  sensitive = false
  default   = ""
}

variable "jsc_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jsc_applicationid" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jsc_applicationsecret" {
  type      = string
  sensitive = true
  default   = ""
}

## Define Okta-related variables
variable "tje_okta_clientid" {
  type    = string
  default = "0oadb9ke61k2h6JiT1d7"
}

variable "tje_okta_orgdomain" {
  type    = string
  default = "sso.tryjamf.com"
}

variable "include_categories" {
  type    = bool
  default = false
}

variable "include_computer_management_settings" {
  type    = bool
  default = false
}
