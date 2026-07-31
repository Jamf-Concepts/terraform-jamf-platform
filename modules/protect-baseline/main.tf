# -----------------------------------------------------------------------------
# Protect Baseline Module
# -----------------------------------------------------------------------------
# The shared baseline every customer calls. One definition of "good", applied to
# every tenant. The only thing that varies is the values passed in from each
# customer.auto.tfvars.
#
# Product tiers:
#   "standard"   threat prevention only (default)
#   "enhanced"   threat prevention plus removable storage device controls
#
# Add a capability here and every customer picks it up on their next apply.
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
    jamfplatform = {
      source  = "Jamf-Concepts/jamfplatform"
      version = ">= 0.25.1"
    }
  }
}

# --- Provider configuration -------------------------------------------------
#
# Providers are configured HERE, inside the module, rather than in each
# customer's root module. That is a deliberate trade-off worth understanding
# before you copy it:
#
#   What it buys — a customer workspace is four small files (main.tf,
#   terraform.tf, customer.auto.tfvars, outputs.tf) with no provider plumbing to
#   keep in sync across fifty directories. Credentials arrive as module inputs,
#   which the onboarding script wires to GitHub Environment secrets once.
#
#   What it costs — a module that configures its own providers cannot be called
#   with `count`, `for_each` or `depends_on`, and cannot be given an aliased
#   provider by its caller. If you need one workspace to reach two tenants, move
#   these blocks into the customer root module and pass them in.
#
# Terraform's guidance is to configure providers only in root modules. The
# limitation is acceptable here because the fan-out is one module call per
# workspace, and the isolation boundary is the workspace, not the module.

provider "jamfprotect" {
  url           = var.protect_url
  client_id     = var.protect_client_id
  client_secret = var.protect_client_password
}

# Reaches Jamf Pro through the Platform API gateway, so a customer is identified
# by a regional base_url (us / eu / apac, shared between customers in the same
# region) plus a tenant UUID, not by a Jamf Pro hostname.
provider "jamfplatform" {
  base_url      = var.platform_base_url
  client_id     = var.platform_client_id
  client_secret = var.platform_client_secret
  tenant_id     = var.platform_tenant_id
}

# --- Feature flags ----------------------------------------------------------
# Derived once so the resource files read as plain conditionals instead of
# repeating the tier comparison in every `count`.

locals {
  # Device controls are an Enhanced-tier capability.
  enable_device_controls = var.product_tier == "enhanced"

  # Data forwarding switches on as soon as a SIEM destination is configured.
  enable_data_forwarding = var.sentinel != null

  # Telemetry collection is opt-in per customer.
  enable_telemetry = var.enable_telemetry
}
