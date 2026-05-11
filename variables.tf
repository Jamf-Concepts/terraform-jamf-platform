variable "jamfpro_instance_fqdn" {
  type        = string
  description = "Full URL of your Jamf Pro instance, e.g. https://yourcompany.jamfcloud.com"
}

variable "jamfpro_client_id" {
  type      = string
  sensitive = true
}

variable "jamfpro_client_secret" {
  type      = string
  sensitive = true
}
