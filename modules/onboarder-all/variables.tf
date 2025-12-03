## Define Jamf Pro provider variables (populated by .tfvars file)
variable "jamfpro_instance_url" {
  description = "Jamf Pro Instance name."
  type        = string
  default     = ""
}

variable "jamfpro_auth_method" {
  description = "Jamf Pro Auth Method."
  type        = string
  default     = "oauth2" #basic or oauth2
}

variable "jamfpro_client_id" {
  description = "Jamf Pro Client ID for authentication."
  type        = string
  default     = ""
}

variable "jamfpro_client_secret" {
  description = "Jamf Pro Client Secret for authentication."
  type        = string
  sensitive   = true
  default     = ""
}

variable "jamfpro_username" {
  description = "Jamf Pro username used for authentication."
  type        = string
  default     = ""
}

variable "jamfpro_password" {
  description = "Jamf Pro password used for authentication."
  type        = string
  sensitive   = true
  default     = ""
}


## Define JSC provider variables (populated by .tfvars file)
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

variable "jsc_applicationid" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jsc_applicationsecret" {
  type      = string
  sensitive = true
  default   = ""
}

/*
variable "VPCId" {
  type      = string
  sensitive = true
  default   = ""
}

variable "SubnetId" {
  type      = string
  sensitive = true
  default   = ""
}

variable "CertificatePrivateKey" {
  type      = string
  sensitive = true
  default   = ""
}

variable "CertificateBody" {
  type      = string
  sensitive = true
  default   = ""
}

variable "aws_region" {
  type      = string
  sensitive = true
  default   = ""
}
*/

## Define Okta-related variables
variable "tje_okta_clientid" {
  type    = string
  default = "0oa1qa4x0qj2Jzeco1d8"
}

variable "tje_okta_orgdomain" {
  type    = string
  default = "jamf-harbor.okta.com"
}

variable "include_mobile_cis_lvl1_benchmark" {
  type    = bool
  default = false
}

variable "include_mac_cis_lvl1_benchmark" {
  type    = bool
  default = false
}

variable "include_mac_stig_benchmark" {
  type    = bool
  default = false
}

variable "include_mobile_stig_benchmark" {
  type    = bool
  default = false
}

variable "include_mac_800_171_benchmark" {
  type    = bool
  default = false
}

variable "include_mac_cmmc_lvl1_benchmark" {
  type    = bool
  default = false
}



## Define demo config variables
variable "include_jsc_demo_config" {
  type    = bool
  default = false
}

variable "include_jamfpro_demo_config" {
  type    = bool
  default = false
}

variable "include_jsc_dp_only" {
  type    = bool
  default = false
}

variable "include_jsc_mtd_only" {
  type    = bool
  default = false
}

variable "include_jsc_all_services" {
  type    = bool
  default = false
}

variable "include_jsc_ap_adobe" {
  type    = bool
  default = false
}

variable "include_jsc_ap_atlassian" {
  type    = bool
  default = false
}

variable "include_jsc_ap_bluejeans" {
  type    = bool
  default = false
}

variable "include_jsc_ap_box" {
  type    = bool
  default = false
}

variable "include_jsc_ap_docusign" {
  type    = bool
  default = false
}

variable "include_jsc_ap_dropbox" {
  type    = bool
  default = false
}

variable "include_jsc_ap_github" {
  type    = bool
  default = false
}

variable "include_jsc_ap_google" {
  type    = bool
  default = false
}

variable "include_jsc_ap_hubspot" {
  type    = bool
  default = false
}

variable "include_jsc_ap_mailchimp" {
  type    = bool
  default = false
}

variable "include_jsc_ap_mathworks" {
  type    = bool
  default = false
}

variable "include_jsc_ap_microsoft" {
  type    = bool
  default = false
}

variable "include_jsc_ap_my_ip" {
  type    = bool
  default = false
}

variable "include_jsc_ap_okta" {
  type    = bool
  default = false
}

variable "include_jsc_ap_salesforce" {
  type    = bool
  default = false
}

variable "include_jsc_ap_servicenow" {
  type    = bool
  default = false
}

variable "include_jsc_ap_slack" {
  type    = bool
  default = false
}

variable "include_jsc_ap_snowflake" {
  type    = bool
  default = false
}

variable "include_jsc_ap_splunk" {
  type    = bool
  default = false
}

variable "include_jsc_ap_square" {
  type    = bool
  default = false
}

variable "include_jsc_ap_twilio" {
  type    = bool
  default = false
}

variable "include_jsc_ap_webex" {
  type    = bool
  default = false
}

variable "include_jsc_ap_workday" {
  type    = bool
  default = false
}

variable "include_jsc_ap_zendesk" {
  type    = bool
  default = false
}

variable "include_jsc_ap_zoom" {
  type    = bool
  default = false
}

variable "include_jsc_uemc" {
  type    = bool
  default = false
}

variable "enable_jsc_uemc" {
  type    = bool
  default = false
}

variable "enable_jsc_uemc_output" {
  type    = bool
  default = false
}

variable "include_jsc_ztna" {
  type    = bool
  default = false
}

variable "include_jsc_network_relay" {
  type    = bool
  default = false
}

variable "include_jsc_block_pages" {
  type    = bool
  default = false
}

variable "include_jsc_mtd_dp_only" {
  type    = bool
  default = false
}

variable "include_jsc_ztna_dp_only" {
  type    = bool
  default = false
}

variable "include_jsc_ztna_mtd_only" {
  type    = bool
  default = false
}

variable "block_page_logo" {
  type      = string
  sensitive = true
  default   = ""
}

variable "support_files_path_prefix" {
  type    = string
  default = ""
}

variable "activation_profile_target" {
  type    = string
  default = ""
}

variable "include_microsoft_edge" {
  type    = bool
  default = false
}

variable "include_box_drive" {
  type    = bool
  default = false
}

variable "include_nudge" {
  type    = bool
  default = false
}

variable "include_adobe_creative_cloud" {
  type    = bool
  default = false
}

variable "include_text_expander" {
  type    = bool
  default = false
}

variable "include_google_chrome" {
  type    = bool
  default = false
}

variable "include_mozilla_firefox" {
  type    = bool
  default = false
}

variable "include_slack" {
  type    = bool
  default = false
}

variable "include_dropbox" {
  type    = bool
  default = false
}

variable "include_google_drive" {
  type    = bool
  default = false
}

variable "include_jamf_composer" {
  type    = bool
  default = false
}

variable "include_pppc_utility" {
  type    = bool
  default = false
}

variable "include_jamfcheck" {
  type    = bool
  default = false
}

variable "include_zoom" {
  type    = bool
  default = false
}

variable "include_jamf_protect_trial_kickstart" {
  type    = bool
  default = false
}

variable "include_categories" {
  type    = bool
  default = false
}

variable "include_computer_management_settings" {
  type    = bool
  default = false
}


variable "include_mobile_device_kickstart" {
  type    = bool
  default = false
}


variable "include_filevault" {
  type    = bool
  default = false
}

variable "include_rosetta" {
  type    = bool
  default = false
}

variable "include_qol_smart_groups" {
  type    = bool
  default = false
}

variable "include_microsoft_365" {
  type    = bool
  default = false
}

variable "include_admin_tools" {
  type    = bool
  default = false
}

variable "include_passwordless_ssoe" {
  type    = bool
  default = false
}

variable "include_jc_privilege_elevation" {
  type    = bool
  default = false
}

variable "include_defender" {
  type    = bool
  default = false
}

variable "include_crowdstrike" {
  type    = bool
  default = false
}
