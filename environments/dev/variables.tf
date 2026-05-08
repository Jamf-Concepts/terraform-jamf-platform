# --------------------------------------------------------------------
# Jamf Pro
# --------------------------------------------------------------------

variable "jamfpro_instance_fqdn" {
  description = "Fully qualified URL of the Jamf Pro tenant for this environment, including https:// (e.g. https://yourcompany-dev.jamfcloud.com)."
  type        = string
}

variable "jamfpro_client_id" {
  description = "OAuth2 Client ID created under API Roles and Clients in Jamf Pro."
  type        = string
  sensitive   = true
}

variable "jamfpro_client_secret" {
  description = "OAuth2 Client Secret for the Jamf Pro API client."
  type        = string
  sensitive   = true
}

# --------------------------------------------------------------------
# Jamf Platform
# --------------------------------------------------------------------

variable "jamfplatform_base_url" {
  description = "Jamf Platform API base URL for your region. One of: https://us.apigw.jamf.com, https://eu.apigw.jamf.com, https://apac.apigw.jamf.com."
  type        = string
}

variable "jamfplatform_tenant_id" {
  description = "Tenant UUID used to scope all Jamf Platform API requests."
  type        = string
}

variable "jamfplatform_client_id" {
  description = "OAuth2 Client ID for the Jamf Platform API."
  type        = string
  sensitive   = true
}

variable "jamfplatform_client_secret" {
  description = "OAuth2 Client Secret for the Jamf Platform API."
  type        = string
  sensitive   = true
}

# --------------------------------------------------------------------
# Apple-issued token paths
#
# These match the convention used by the jamformer tool: the variable
# holds a *path* to a token file on disk, and resources read it via
# file(var.xxx). Place the actual token files in:
#
#   support_files/device_enrollment_tokens/   (.p7m files from ABM/ASM)
#   support_files/volume_purchasing_tokens/   (.vpptoken files from ABM/ASM)
#
# The variable name suffix matches the resource label it feeds. If you
# add a second device enrollment server resource called "kiosks", add a
# matching variable `ade_token_path_kiosks` and reference it in the
# resource as `encoded_token = file(var.ade_token_path_kiosks)`.
# --------------------------------------------------------------------

variable "ade_token_path_default" {
  description = "Path to the .p7m Automated Device Enrollment server token file from Apple Business Manager or Apple School Manager. Read at apply time via file(); place the file in support_files/device_enrollment_tokens/."
  type        = string
  default     = null
}

variable "vpp_token_path_default" {
  description = "Path to the .vpptoken Volume Purchasing service token file from Apple Business Manager or Apple School Manager. Read at apply time via file(); place the file in support_files/volume_purchasing_tokens/."
  type        = string
  default     = null
}

# --------------------------------------------------------------------
# Module configuration
# --------------------------------------------------------------------

variable "wifi_ssid" {
  description = "SSID of the Wi-Fi network deployed to mobile devices via configuration profile."
  type        = string
  default     = "Pretend Co Wi-Fi"
}

variable "wifi_password" {
  description = "Password for the Wi-Fi network deployed to mobile devices."
  type        = string
  sensitive   = true
}
