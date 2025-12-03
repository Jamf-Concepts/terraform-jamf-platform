### Define Jamf Protect for macOS integration
variable "include_jamf_protect_for_macOS" {
  type    = bool
  default = false
}

variable "jamfprotect_url" {
  type    = string
  default = ""
}

variable "jamfprotect_clientID" {
  type    = string
  default = ""
}

variable "jamfprotect_client_password" {
  type      = string
  sensitive = true
  default   = ""
}
