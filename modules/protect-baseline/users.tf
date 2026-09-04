# -----------------------------------------------------------------------------
# Users: Console Access
# -----------------------------------------------------------------------------
# Who from your team can log into each customer's Protect console. Edit one list
# in variables.tf when someone joins or leaves and every tenant is corrected on
# its next apply, instead of auditing fifty consoles by hand.
#
# Both lists default to empty, so no users are created until you populate them.
# They are fleet-wide by design: set them in variables.tf, not per customer.
#
# The IDs below are Jamf Protect built-ins:
#   identity_provider_id = "1"   the Jamf Account IdP
#   role_ids             = "2"   Full Admin, "1" Read Only
#   group_ids            = "1"   the default group
#
# Confirm them against a tenant first. They are stable in practice, but they are
# IDs rather than names and nothing guarantees a tenant matches.
#
# Leave the Jamf Account that created the tenant out of these lists. It is
# already associated with the tenant and adding it here conflicts.
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
