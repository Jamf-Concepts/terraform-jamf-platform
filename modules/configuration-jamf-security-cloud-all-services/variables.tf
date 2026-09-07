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

variable "jamfplatform_environment_id" {
  description = "Environment UUID sent as X-Tenant-Id when calling the JSC UEM Connect API directly (see main.tf's deploy_activation_profile)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "uem_connect_dependency" {
  description = "The sibling UEM Connect module's connector id, passed through only to order this module's activation-profile deploy after that connector exists."
  type        = string
  default     = ""
}
