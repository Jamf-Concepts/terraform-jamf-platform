# -----------------------------------------------------------------------------
# Users — Console Access
# -----------------------------------------------------------------------------
# Who from your team can log into each customer's Protect console, defined once
# and applied everywhere. When someone joins or leaves, you edit one list in
# variables.tf and every tenant is corrected on its next apply — rather than
# auditing fifty consoles by hand.
#
# Both lists default to empty, so this module creates no users until you
# populate them. They are fleet-wide by design: set them once in
# modules/protect-baseline/variables.tf rather than per customer.
#
# The identity_provider_id, role_ids and group_ids below are Jamf Protect
# built-in IDs:
#   identity_provider_id = "1"  — the Jamf Account IdP. A tenant using a
#                                 different IdP configuration needs a different
#                                 value here.
#   role_ids             = "2"  — Full Admin        "1" — Read Only
#   group_ids            = "1"  — the default group
#
# Confirm these against a tenant before first use: they are stable in practice
# but they are IDs, not names, and nothing stops a tenant differing.
#
# One caveat worth knowing: the Jamf Account used to create the tenant is
# already associated with it and does not need a user resource. Adding it here
# will conflict, so leave the tenant creator out of these lists.
# -----------------------------------------------------------------------------

resource "jamfprotect_user" "full_admin" {
  for_each = toset(var.full_admin_users)

  email                    = each.value
  identity_provider_id     = "1"
  role_ids                 = ["2"]
  group_ids                = ["1"]
  send_email_notifications = true
  email_severity           = "High"
}

resource "jamfprotect_user" "read_only" {
  for_each = toset(var.read_only_users)

  email                    = each.value
  identity_provider_id     = "1"
  role_ids                 = ["1"]
  group_ids                = []
  send_email_notifications = true
  email_severity           = "Medium"
}
