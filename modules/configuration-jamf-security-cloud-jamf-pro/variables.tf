variable "jamfplatform_base_url" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfpro_instance_url" {
  description = "Full URL of the Jamf Pro instance (e.g. https://letstest.jamfcloud.com)."
  type        = string
  default     = ""
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

variable "jamfplatform_client_id" {
  description = "Jamf Pro Client ID for authentication."
  type        = string
  default     = ""
}

variable "jamfplatform_client_secret" {
  description = "Jamf Pro Client Secret for authentication."
  type        = string
  sensitive   = true
  default     = ""
}

variable "random_string" {
  type    = string
  default = ""
}

variable "uem_connect_already_exists_id" {
  description = "Id of an existing UEM Connect integration for this tenant, if the caller found one before this run. When non-empty, this module skips creating a new integration (Jamf Security Cloud allows only one per tenant) and reuses this id instead."
  type        = string
  default     = ""
}


