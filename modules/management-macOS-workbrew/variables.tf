## Define miscellaneous variables
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

variable "include_workbrew" {
  type    = bool
  default = false
}

variable "workbrew_workspace_api_key" {
  description = "Workbrew Workspace API Key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "random_string" {
  type    = string
  default = ""
}