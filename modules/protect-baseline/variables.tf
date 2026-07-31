# -----------------------------------------------------------------------------
# Input Variables
# -----------------------------------------------------------------------------
# This file is the menu. Everything a customer is allowed to vary appears here
# as a variable with a safe default; anything that is not here cannot be
# ordered. When a customer asks for something new, it gets added here and
# becomes available to everyone in the same, reviewed shape — rather than being
# applied to one tenant by hand.
#
# Credentials arrive as TF_VAR_* environment variables from GitHub Environment
# secrets at run time. They are never committed and never defaulted.
# -----------------------------------------------------------------------------

# --- Jamf Protect Credentials -----------------------------------------------

variable "protect_url" {
  description = "Customer Protect tenant URL (e.g. https://tenant.protect.jamfcloud.com)"
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
# Used to reach the customer's Jamf Pro instance through the Platform API
# gateway. Note this is a regional endpoint plus a tenant UUID, not a per-
# instance hostname — see the provider block in main.tf.

variable "platform_base_url" {
  description = "Jamf Platform API gateway base URL for this customer's region (e.g. https://eu.apigw.jamf.com)"
  type        = string

  validation {
    # A tenant URL here is the most likely mistake, and it produces a confusing
    # auth failure rather than an obvious one.
    condition     = can(regex("^https://[a-z]+\\.(stage\\.)?apigw\\.jamf(nebula)?\\.com/?$", var.platform_base_url))
    error_message = "platform_base_url must be a Jamf Platform API gateway URL, e.g. https://us.apigw.jamf.com, https://eu.apigw.jamf.com or https://apac.apigw.jamf.com — not a Jamf Pro tenant URL."
  }
}

variable "platform_tenant_id" {
  description = "Jamf Platform tenant UUID. Scopes every API request to this customer."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.platform_tenant_id))
    error_message = "platform_tenant_id must be a UUID."
  }
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
# The two bases on the menu. A validation block turns a typo into a clear plan
# error instead of a tenant that silently gets the wrong configuration.

variable "product_tier" {
  description = "Product tier: standard (threat prevention) or enhanced (threat prevention + device controls)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "enhanced"], var.product_tier)
    error_message = "product_tier must be one of: standard, enhanced."
  }
}

# --- Device Controls --------------------------------------------------------

variable "removable_storage_default_permission" {
  description = "Default permission for the removable storage control set. Prevent is the standard for all enhanced customers; set Read Only in customer.auto.tfvars only where a customer has a documented reason."
  type        = string
  default     = "Prevent"

  validation {
    condition     = contains(["Prevent", "Read Only"], var.removable_storage_default_permission)
    error_message = "removable_storage_default_permission must be one of: Prevent, Read Only."
  }
}

# --- Per-Customer Removable Storage Overrides -------------------------------
# Four override shapes, matching the four ways Jamf Protect can identify a
# device: by vendor, by vendor+product pair, by serial number, or by whether
# the device is encrypted. All default to empty, so a customer with no
# exceptions carries no exception configuration at all.

variable "removable_storage_override_vendor_id" {
  description = "Vendor ID overrides for the removable storage control set. Only used when product_tier is enhanced."
  type = list(object({
    vendor_ids                 = list(string)
    permission                 = string
    apply_to                   = optional(string, "All")
    local_notification_message = optional(string)
  }))
  default = []
}

variable "removable_storage_override_product_id" {
  description = "Product ID overrides for the removable storage control set. Only used when product_tier is enhanced."
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
  description = "Serial number overrides for the removable storage control set. Only used when product_tier is enhanced."
  type = list(object({
    serial_numbers             = list(string)
    permission                 = string
    apply_to                   = optional(string, "All")
    local_notification_message = optional(string)
  }))
  default = []
}

variable "removable_storage_override_encrypted_devices" {
  description = "Encrypted device overrides for the removable storage control set. Only used when product_tier is enhanced."
  type = list(object({
    permission                 = string
    local_notification_message = optional(string)
  }))
  default = []
}

# --- Per-Customer Threat Prevention Exception Sets --------------------------

variable "exception_sets" {
  description = "Per-customer threat prevention exception sets. Each map key becomes an exception set name in the console. Processes and paths are converted to the provider's rule structure by exception_sets.tf."
  type = map(object({
    processes = optional(list(string), [])
    paths     = optional(list(string), [])
  }))
  default = {}
}

# --- Console Users ----------------------------------------------------------
# Fleet-wide lists: these apply to every customer tenant, not per customer.
# Populate with your own team's addresses. Leave empty to manage console
# access outside Terraform.
#
# Do not include the Jamf Account that created a tenant — it is already
# associated with that tenant (see users.tf).

variable "full_admin_users" {
  description = "Email addresses provisioned as Full Admin console users in every customer tenant."
  type        = list(string)
  default     = []
  # Example:
  # default = [
  #   "first.engineer@example.com",
  #   "second.engineer@example.com",
  # ]
}

variable "read_only_users" {
  description = "Email addresses provisioned as Read Only console users in every customer tenant."
  type        = list(string)
  default     = []
  # Example:
  # default = [
  #   "service.desk@example.com",
  # ]
}

# --- Telemetry --------------------------------------------------------------

variable "enable_telemetry" {
  description = "Enable Jamf Protect telemetry collection. When true, a telemetry configuration is created and attached to all plans."
  type        = bool
  default     = false
}

# --- SIEM Data Forwarding ---------------------------------------------------

variable "sentinel" {
  description = "Microsoft Sentinel data forwarding configuration. Null (the default) means no data forwarding resource is created at all. When provided, alerts and telemetry are forwarded to the specified Sentinel workspace."
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
  description = "Microsoft Sentinel application secret. Passed via TF_VAR_sentinel_app_secret from a GitHub Environment secret. Required when sentinel is configured."
  type        = string
  sensitive   = true
  default     = ""
}
