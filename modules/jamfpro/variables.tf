# Module input variables. The root module (environments/dev/main.tf) reads
# token files from disk and passes the encoded content here. Both are required —
# environments without ADE or VPP should omit the call to this module or
# set up separate module instances per token type.

variable "ade_token_encoded_default" {
  description = "Base64-encoded contents of the .p7m Automated Device Enrollment server token. Typically computed by the caller as filebase64(var.ade_token_path_default)."
  type        = string
  sensitive   = true
}

variable "vpp_token_default" {
  description = "Contents of the .vpptoken Volume Purchasing service token, with surrounding whitespace trimmed. Typically computed by the caller as trimspace(file(var.vpp_token_path_default))."
  type        = string
  sensitive   = true
}

variable "wifi_ssid" {
  description = "SSID of the Wi-Fi network deployed to mobile devices via configuration profile."
  type        = string
  default     = "Pretend Co Wi-Fi"
}

variable "wifi_password" {
  description = "Password for the Wi-Fi network deployed to mobile devices. Stored in Terraform state — supply via terraform.tfvars or TF_VAR_wifi_password and rotate as you would any other credential."
  type        = string
  sensitive   = true
}
