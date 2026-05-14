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
  description = "Tenant UUID — click the tenant pill in the Integration details panel at account.jamf.com"
}
