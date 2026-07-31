# -----------------------------------------------------------------------------
# Customer Root Module — example-customer
# -----------------------------------------------------------------------------
# One module call, and a variable declaration for every input that call needs.
# There is no configuration in here: the whole baseline lives in
# modules/protect-baseline. This file exists to say "this customer, these
# values, that module".
#
# Terraform has no variable inheritance — a root module must declare every
# variable it passes down, even when the module already declares it. That is
# why this file is longer than it looks like it should be. The declarations are
# deliberately thin: no descriptions duplicated from the module, no defaults
# that could drift from the module's, just types.
#
# Where values come from:
#   Credentials         → TF_VAR_* environment variables, set from GitHub
#                         Environment secrets by the workflows. Never committed.
#   Tier and overrides  → customer.auto.tfvars, in this directory. Committed,
#                         reviewed, and the only file that differs in substance
#                         between customers.
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

# --- Jamf Pro Credentials ---------------------------------------------------

variable "jpro_url" {
  description = "Customer Jamf Pro instance URL"
  type        = string
}

variable "jpro_client_id" {
  description = "Jamf Pro OAuth2 API client ID"
  type        = string
  sensitive   = true
}

variable "jpro_client_secret" {
  description = "Jamf Pro OAuth2 API client secret"
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
# The module call — this is the entire customer configuration.
# -----------------------------------------------------------------------------

module "protect" {
  source = "../../modules/protect-baseline"

  protect_url             = var.protect_url
  protect_client_id       = var.protect_client_id
  protect_client_password = var.protect_client_password

  jpro_url           = var.jpro_url
  jpro_client_id     = var.jpro_client_id
  jpro_client_secret = var.jpro_client_secret

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
# Anything that should exist for THIS customer only can be declared here,
# alongside the module call, rather than being added to the shared module.
#
# Use this sparingly. A resource here is a snowflake: it will not be picked up
# by the next customer, and nobody reviewing the shared module will know it
# exists. If two customers need the same thing, it belongs in the module behind
# a variable instead — that is the difference between adding to the menu and
# cooking something off-menu.
