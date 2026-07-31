# -----------------------------------------------------------------------------
# Jamf Pro — Protect Registration
# -----------------------------------------------------------------------------
# One pipeline, two products, one apply: the same run that builds the Protect
# configuration registers Protect in the customer's Jamf Pro instance, using the
# Read Only client created earlier in this module. Maps to Settings → Jamf apps →
# Jamf Protect.
#
# Singleton — one per tenant. Creating it over an existing registration does not
# fail; the server overwrites in place. Onboarding checks for that first.
#
# depends_on: plans must exist before registration, or the sync it triggers finds
# nothing to push and the configuration profiles land empty.
# -----------------------------------------------------------------------------

resource "jamfplatform_pro_jamf_protect" "registration" {
  # The GraphQL endpoint, not the console URL. trimsuffix guards against a
  # trailing slash, which the server echoes back and shows as permanent drift.
  api_url = "${trimsuffix(var.protect_url, "/")}/graphql"

  client_id = jamfprotect_api_client.managed_protect_standard.id
  password  = jamfprotect_api_client.managed_protect_standard.password

  # Rotation trigger for the write-only password. Static 1 is correct: the
  # password only changes if the API client is replaced, and a replaced client
  # also has a new id, which re-registers and re-sends the password anyway.
  password_wo_version = 1

  auto_install = true

  timeouts = {
    create = "90s"
  }

  depends_on = [
    jamfprotect_plan.managed_protect_standard,
    jamfprotect_plan.managed_protect_enhanced,
  ]
}
