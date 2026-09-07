variable "jamfplatform_base_url" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfplatform_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfplatform_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "uem_connect_dependency" {
  description = "The sibling UEM Connect module's connector id, passed through only to order this module's deploy actions after that connector exists."
  type        = string
  default     = ""
}
