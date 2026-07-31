# -----------------------------------------------------------------------------
# Protect Baseline Module
# -----------------------------------------------------------------------------
# The shared baseline every customer calls. One module, one definition of
# "good", applied to every tenant. The only thing that varies between
# customers is the values passed in from their customer.auto.tfvars.
#
# Product tiers:
#   - "standard"  — threat prevention only (default)
#   - "enhanced"  — threat prevention + removable storage device controls
#
# Add a capability here once and every customer picks it up on their next
# apply. Nobody logs into fifty consoles to make the same change fifty times.
# -----------------------------------------------------------------------------

terraform {
  # 1.14 is the floor because the Out-of-Band Resource Detection workflow
  # (.github/workflows/reconcile.yaml) uses `terraform query`, which was
  # introduced in Terraform 1.14. Plan and apply alone would work on 1.11+.
  required_version = ">= 1.14.0"

  required_providers {
    jamfprotect = {
      source  = "Jamf-Concepts/jamfprotect"
      version = ">= 0.10.0"
    }
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.41.0"
    }
  }
}

# --- Provider configuration -------------------------------------------------
#
# Providers are configured HERE, inside the module, rather than in each
# customer's root module. That is a deliberate trade-off worth understanding
# before you copy it:
#
#   Why it is done this way — every customer workspace is then genuinely
#   three files (main.tf, terraform.tf, customer.auto.tfvars) with no provider
#   plumbing to keep in sync across fifty directories. Credentials arrive as
#   module inputs, which the onboarding script wires to GitHub Environment
#   secrets once.
#
#   What it costs — a module that configures its own providers cannot be
#   called with `count`, `for_each` or `depends_on`, and cannot be given an
#   aliased provider by its caller. If you ever need one workspace to talk to
#   two tenants, move these two blocks up into the customer root module and
#   pass them in explicitly.
#
# Terraform's own guidance is to configure providers only in root modules. We
# accept the limitation because the fan-out here is one module call per
# workspace, and the isolation boundary is the workspace, not the module.

provider "jamfprotect" {
  url           = var.protect_url
  client_id     = var.protect_client_id
  client_secret = var.protect_client_password
}

provider "jamfpro" {
  jamfpro_instance_fqdn = var.jpro_url
  client_id             = var.jpro_client_id
  client_secret         = var.jpro_client_secret
  auth_method           = "oauth2"

  # Refresh the OAuth2 token 30 seconds before it expires.
  token_refresh_buffer_period_seconds = 30

  jamfpro_load_balancer_lock           = false
  mandatory_request_delay_milliseconds = 0
}

# --- Feature flags ----------------------------------------------------------
# Derived once here so the resource files read as plain conditionals rather
# than repeating the tier comparison in every `count`.

locals {
  # Device controls are an Enhanced-tier capability.
  enable_device_controls = var.product_tier == "enhanced"

  # Data forwarding switches on as soon as a SIEM destination is configured.
  enable_data_forwarding = var.sentinel != null

  # Telemetry collection is opt-in per customer.
  enable_telemetry = var.enable_telemetry
}
