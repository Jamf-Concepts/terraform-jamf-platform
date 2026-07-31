# -----------------------------------------------------------------------------
# API Clients
# -----------------------------------------------------------------------------
# Note the bootstrap problem: Terraform cannot create the credential it needs
# to authenticate to a tenant in the first place. One API client must be made
# by hand in each new Protect console before the first apply — that one is
# deliberately NOT managed here (and is excluded from out-of-band detection in
# scripts/reconcile-out-of-band.sh for exactly that reason).
#
# Everything created below is a credential Terraform issues *after* it is
# already authenticated, for something other than Terraform to consume.
# -----------------------------------------------------------------------------

# --- Jamf Pro registration client -------------------------------------------
# Read Only, and used by jamf_pro.tf to register Protect inside the customer's
# Jamf Pro instance. Terraform creates it and hands the password straight to
# the Jamf Pro resource in the same apply, so the secret never needs to be
# stored or copied by a human.

resource "jamfprotect_api_client" "managed_protect_standard" {
  name = "Managed Protect"
  role_ids = [
    local.read_only_role_id,
  ]
}

# --- Reporting integration client -------------------------------------------
# Paired with the read-only role in role.tf. Its password is exposed as a
# sensitive output (see outputs.tf) because it has to be entered into the
# reporting product by hand — Terraform has no API to push it there.

resource "jamfprotect_api_client" "insights" {
  name = "Jamf-Insights-Integration"
  role_ids = [
    jamfprotect_role.insights.id,
  ]
}
