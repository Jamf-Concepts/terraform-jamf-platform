# -----------------------------------------------------------------------------
# Customer Root Module — staging
# -----------------------------------------------------------------------------
# One module call, plus a variable declaration for every input it needs. No
# configuration lives here; the baseline is all in modules/protect-baseline. This
# file says "this customer, these values, that module".
#
# Terraform has no variable inheritance, so a root module must declare every
# variable it passes down even when the module already declares it. That is why
# the file is long. The declarations are thin on purpose: no descriptions copied
# from the module, no defaults that could drift from it, just types.
#
# Where values come from:
#   Credentials         TF_VAR_* environment variables, set from GitHub
#                       Environment secrets by the workflows. Never committed.
#   Tier and overrides  customer.auto.tfvars, in this directory. Committed and
#                       reviewed, and the only file that differs in substance
#                       between customers.
# -----------------------------------------------------------------------------

# --- Jamf Protect Credentials -----------------------------------------------

variable "protect_url" {
  description = "Customer Protect tenant URL"
  type        = string
}

variable "protect_client_id" {
  description = "Jamf Protect API client ID"
  type        = string
  sensitive   = true
}

variable "protect_client_password" {
  description = "Jamf Protect API client password"
  type        = string
  sensitive   = true
}

# --- Jamf Platform Credentials ----------------------------------------------
# Reaches this customer's Jamf Pro instance via the Platform API gateway. The base
# URL is regional and the tenant is identified by UUID, so no Jamf Pro hostname
# appears here. Validation lives in the module.

variable "platform_base_url" {
  description = "Jamf Platform API gateway base URL for this customer's region"
  type        = string
}

variable "platform_environment_id" {
  description = "Jamf Platform environment UUID"
  type        = string
}

variable "platform_client_id" {
  description = "Jamf Platform API OAuth client ID"
  type        = string
  sensitive   = true
}

variable "platform_client_secret" {
  description = "Jamf Platform API OAuth client secret"
  type        = string
  sensitive   = true
}

# --- Product Tier -----------------------------------------------------------

variable "product_tier" {
  description = "Product tier: standard or enhanced"
  type        = string
  default     = "standard"
}

# --- Device Controls --------------------------------------------------------

variable "removable_storage_default_permission" {
  description = "Default permission for the removable storage control set"
  type        = string
  default     = "Prevent"
}

variable "removable_storage_override_vendor_id" {
  description = "Vendor ID overrides for the removable storage control set"
  type = list(object({
    vendor_ids                 = list(string)
    permission                 = string
    apply_to                   = optional(string, "All")
    local_notification_message = optional(string)
  }))
  default = []
}

variable "removable_storage_override_product_id" {
  description = "Product ID overrides for the removable storage control set"
  type = list(object({
    permission = string
    apply_to   = optional(string, "All")
    product_id = list(object({
      vendor_id  = string
      product_id = string
    }))
    local_notification_message = optional(string)
  }))
  default = []
}

variable "removable_storage_override_serial_number" {
  description = "Serial number overrides for the removable storage control set"
  type = list(object({
    serial_numbers             = list(string)
    permission                 = string
    apply_to                   = optional(string, "All")
    local_notification_message = optional(string)
  }))
  default = []
}

variable "removable_storage_override_encrypted_devices" {
  description = "Encrypted device overrides for the removable storage control set"
  type = list(object({
    permission                 = string
    local_notification_message = optional(string)
  }))
  default = []
}

# --- Exception Sets ---------------------------------------------------------

variable "exception_sets" {
  description = "Per-customer threat prevention exception sets"
  type = map(object({
    processes = optional(list(string), [])
    paths     = optional(list(string), [])
  }))
  default = {}
}

# --- Telemetry --------------------------------------------------------------

variable "enable_telemetry" {
  description = "Enable Jamf Protect telemetry collection"
  type        = bool
  default     = false
}

# --- Microsoft Sentinel Data Forwarding -------------------------------------

variable "sentinel" {
  description = "Microsoft Sentinel data forwarding configuration. Null (the default) disables it."
  type = object({
    directory_id             = string
    application_id           = string
    data_collection_endpoint = string
    alerts_rule_id           = string
    alerts_stream_name       = string
    telemetry_rule_id        = string
    telemetry_stream_name    = string
    app_secret_version       = string
  })
  default = null
}

variable "sentinel_app_secret" {
  description = "Microsoft Sentinel application secret, from a GitHub Environment secret"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------------------------------
# The module call. This is the entire customer configuration.
# -----------------------------------------------------------------------------

module "protect" {
  source = "../../modules/protect-baseline"

  protect_url             = var.protect_url
  protect_client_id       = var.protect_client_id
  protect_client_password = var.protect_client_password

  platform_base_url       = var.platform_base_url
  platform_environment_id = var.platform_environment_id
  platform_client_id      = var.platform_client_id
  platform_client_secret  = var.platform_client_secret

  product_tier = var.product_tier

  removable_storage_default_permission         = var.removable_storage_default_permission
  removable_storage_override_vendor_id         = var.removable_storage_override_vendor_id
  removable_storage_override_product_id        = var.removable_storage_override_product_id
  removable_storage_override_serial_number     = var.removable_storage_override_serial_number
  removable_storage_override_encrypted_devices = var.removable_storage_override_encrypted_devices

  exception_sets      = var.exception_sets
  enable_telemetry    = var.enable_telemetry
  sentinel            = var.sentinel
  sentinel_app_secret = var.sentinel_app_secret
}

# --- Customer-specific resources --------------------------------------------
#
# Anything that should exist for THIS customer only can be declared here, beside
# the module call, rather than added to the shared module.
#
# Use it sparingly. A resource here is a snowflake: the next customer will not
# pick it up, and nobody reviewing the shared module will know it exists. If two
# customers need the same thing, it belongs in the module behind a variable.
