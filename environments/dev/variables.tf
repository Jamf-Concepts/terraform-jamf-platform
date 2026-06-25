# --------------------------------------------------------------------
# Jamf Platform provider configuration variables
# --------------------------------------------------------------------

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
