
variable "jamfpro_instance_fqdn" {
  type      = string
  sensitive = true
  default   = ""
}

variable "radar_user" {
  type      = string
  sensitive = true
  default   = ""
}

variable "okta_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "okta_org_domain" {
  type      = string
  sensitive = true
  default   = ""
}

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

variable "clientid" {
  type      = string
  sensitive = true
  default   = ""
}

variable "clientsecret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "auth_method" {
  type      = string
  sensitive = true
  default   = ""
}

variable "basic_auth_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "basic_auth_username" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfpro_client_id" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jamfpro_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "block_page_logo" {
  type      = string
  sensitive = false
  default   = ""
}

variable "support_files_path_prefix" {
  type    = string
  default = ""
}

variable "enable_jsc_uemc" {
  type    = string
  default = ""
}

variable "enable_jsc_uemc_output" {
  type    = string
  default = ""
}

variable "random_string" {
  type    = string
  default = ""
}


