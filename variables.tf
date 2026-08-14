variable "jamfplatform_base_url" {
  type        = string
  description = "Jamf Platform API gateway URL, e.g. https://us.apigw.jamf.com"
}

variable "jamfplatform_client_id" {
  type      = string
  sensitive = true
}

variable "jamfplatform_client_secret" {
  type      = string
  sensitive = true
}

variable "jamfplatform_tenant_id" {
  type        = string
  description = "Your Jamf tenant UUID"
  sensitive   = true
}
