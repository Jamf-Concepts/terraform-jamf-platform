## Define Jamf Pro provider variables (populated by .tfvars file)
variable "jamfplatform_base_url" {
  description = "Jamf Pro Instance name."
  type        = string
}

variable "jamfplatform_client_id" {
  description = "Jamf Pro Client ID for authentication."
  type        = string
}

variable "jamfplatform_client_secret" {
  description = "Jamf Pro Client Secret for authentication."
  type        = string
  sensitive   = true
}

variable "jamfplatform_pro_username" {
  description = "Jamf Pro username used for authentication."
  type        = string
  default     = ""
}

variable "jamfplatform_pro_password" {
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

variable "jsc_application_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jsc_application_secret" {
  type      = string
  sensitive = true
  default   = ""
}