# -----------------------------------------------------------------------------
# Terraform Configuration — staging
# -----------------------------------------------------------------------------
# Backend and version constraints for this customer workspace.
#
# This is the file that makes multi-tenancy safe. The customer name is baked
# into the state key, so every customer reads and writes a completely separate
# state object. A bad apply against one tenant cannot touch another's state.
#
# The backend below is S3, as a working example. Any backend that gives you a
# per-tenant path and state locking works the same way — swap it for yours. See
# the README "State backend" section for what else changes if you do.
#
# BEFORE YOUR FIRST ONBOARDING, point this at storage you own. Backend blocks
# cannot reference variables, so it is a literal edit; use `terraform init
# -backend-config=...` if you would rather supply values at init time. With S3,
# the bucket must also be set as the STATE_BUCKET repository variable, which the
# destroy and handover workflows use to remove state objects.
#
#   encrypt      = true  — state is encrypted at rest. State records credentials
#                          in plain text, so treat the store as a secret.
#   use_lockfile = true  — S3-native locking. Two operations against the same
#                          customer cannot run at once; the second is blocked
#                          rather than corrupting state.
#
# The onboarding script fills the customer name in automatically. However it is
# set, the state key must always match the customer directory name.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.14.0"

  # Declared at the root so `terraform query` (used by the Out-of-Band Resource
  # Detection workflow, .github/workflows/reconcile.yaml) can resolve a provider
  # for its root-level `list` blocks. Plan and apply configure the provider
  # inside the protect-baseline module instead, so this root declaration is
  # inert for those operations — it is only instantiated by the query.
  required_providers {
    jamfprotect = {
      source  = "Jamf-Concepts/jamfprotect"
      version = ">= 0.10.0"
    }
  }

  backend "s3" {
    bucket       = "replace-me-jamfprotect-tfstate"
    key          = "customers/staging/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
