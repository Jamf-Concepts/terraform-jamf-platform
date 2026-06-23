## Define miscellaneous variables

variable "support_files_path_prefix" {
  type    = string
  default = ""
}
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

variable "random_string" {
  type    = string
  default = ""
}
