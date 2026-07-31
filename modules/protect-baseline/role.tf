# -----------------------------------------------------------------------------
# Roles
# -----------------------------------------------------------------------------
# Two roles are involved, and only one of them is created here.
# -----------------------------------------------------------------------------

# --- Read Only (data source) ------------------------------------------------
# "Read Only" is a built-in role in every Protect tenant, with a different ID in
# each. Reading it by name keeps hardcoded UUIDs and import blocks out of the
# module. Same pattern as the Jamf-managed exception set in exception_sets.tf.

data "jamfprotect_roles" "all" {}

locals {
  read_only_role_id = one([for r in data.jamfprotect_roles.all.roles : r.id if r.name == "Read Only"])
}

# --- Reporting integration role ---------------------------------------------
# A least-privilege read-only role for an external reporting or analytics
# integration. Here that is Jamf Insights, but the pattern suits any consumer
# that reads alert and inventory data without changing configuration.
#
# Grant only the read permissions the integration needs. Adding permissions here
# is a reviewed change; adding them in the console is drift.

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
