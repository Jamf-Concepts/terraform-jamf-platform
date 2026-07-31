# -----------------------------------------------------------------------------
# Terraform Configuration — example-customer
# -----------------------------------------------------------------------------
# Backend and version constraints for this customer workspace.
#
# This is the file that makes multi-tenancy safe. The customer name is baked
# into the state key, so every customer reads and writes a completely separate
# state object. A bad apply against one tenant cannot touch another's state.
#
#   encrypt      = true  — state encrypted at rest (state holds secrets in
#                          plain text; treat the bucket accordingly)
#   use_lockfile = true  — native S3 state locking. Two operations against the
#                          same customer cannot run at once; the second is
#                          blocked rather than corrupting state.
#
# AWS credentials come from environment variables — repository-level secrets in
# CI/CD, or exported locally before `terraform init`.
#
# BEFORE YOUR FIRST ONBOARDING you must set `bucket` and `region` below to your
# own values. Backend blocks cannot use variables or interpolation, so this is
# a literal edit. The bucket name must also be set as the repository variable
# STATE_BUCKET, which the destroy and handover workflows use to remove state
# objects — the two must agree.
#
# The onboarding script fills the customer name in automatically. However it is
# set, the S3 key must always match the customer directory name.
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
    key          = "customers/example-customer/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
