# -----------------------------------------------------------------------------
# Jamf Pro — Protect Registration
# -----------------------------------------------------------------------------
# One pipeline, two products, one apply. This is the resource that proves the
# point: the same run that builds the Protect configuration reaches into the
# customer's Jamf Pro instance and registers Protect there, using the Read Only
# client created earlier in this module.
#
# auto_install = true makes Jamf Pro deploy the Protect agent to managed
# computers as part of the registration handshake.
#
# depends_on: all plans must exist before registration. The handshake triggers
# a sync from Protect to Jamf Pro; if plans do not exist yet, that sync finds
# nothing to push and the configuration profiles land empty.
# -----------------------------------------------------------------------------

resource "jamfpro_jamf_protect" "registration" {
  protect_url  = var.protect_url
  client_id    = jamfprotect_api_client.managed_protect_standard.id
  password     = jamfprotect_api_client.managed_protect_standard.password
  auto_install = true

  timeouts {
    create = "90s"
  }

  depends_on = [
    jamfprotect_plan.managed_protect_standard,
    jamfprotect_plan.managed_protect_enhanced,
  ]
}
