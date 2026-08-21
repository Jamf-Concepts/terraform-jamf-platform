variable "jamfplatform_base_url" {
  description = "Jamf Platform API gateway URL."
  type        = string
}

variable "jamfplatform_client_id" {
  description = "Jamf Platform Client ID for authentication."
  type        = string
}

variable "jamfplatform_client_secret" {
  description = "Jamf Platform Client Secret for authentication."
  type        = string
  sensitive   = true
}

variable "baseline_id" {
  description = "Compliance Benchmarks Engine baseline_id to deploy (e.g. \"cis_lvl1\"). Accepted values are server-defined by the Jamf Platform API, not restricted by this provider."
  type        = string
}

variable "benchmark_title" {
  description = "Human-readable title for the deployed benchmark and its device group (e.g. \"CIS Level 1 Benchmark\")."
  type        = string
}
