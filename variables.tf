variable "jamfplatform_base_url" {
  type        = string
  description = "Jamf Platform API gateway URL. US: https://us.apigw.jamf.com, EU: https://eu.apigw.jamf.com, APAC: https://apac.apigw.jamf.com"
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
  description = "Tenant UUID — found in the Jamf admin console under your tenant details"
}

variable "device_group_platform_id" {
  type        = string
  description = "Platform API UUID of the device group to target. See Prerequisites in README.md for how to find it."
}
