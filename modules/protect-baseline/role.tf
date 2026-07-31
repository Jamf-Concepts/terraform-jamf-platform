# -----------------------------------------------------------------------------
# Roles
# -----------------------------------------------------------------------------
# Two roles are involved, and only one of them is created here.
# -----------------------------------------------------------------------------

# --- Read Only (data source) ------------------------------------------------
# "Read Only" is a built-in role present in every Jamf Protect tenant, with a
# different ID in each. Reading it by name means the module never carries a
# hardcoded UUID and never needs an import block. Same pattern as the
# Jamf-managed exception set in exception_sets.tf.

data "jamfprotect_roles" "all" {}

locals {
  read_only_role_id = one([for r in data.jamfprotect_roles.all.roles : r.id if r.name == "Read Only"])
}

# --- Reporting integration role ---------------------------------------------
# A least-privilege read-only role for an external reporting or analytics
# integration — in our service this is Jamf Insights, but the pattern is the
# same for any consumer that needs to read alert and inventory data without
# the ability to change configuration.
#
# Grant only the read permissions the integration actually needs. Adding
# permissions here is a reviewed change; adding them in the console is drift.

resource "jamfprotect_role" "insights" {
  name = "Jamf-Insights-Integration"
  read_permissions = [
    "Account Information",
    "Alerts",
    "Computers",
    "Downloads",
    "Endpoint Threat Prevention",
    "Plans",
    "Telemetry",
  ]
}
