# -----------------------------------------------------------------------------
# reconcile.tfquery.hcl
# -----------------------------------------------------------------------------
# Query configuration for the Out-of-Band Resource Detection workflow
# (.github/workflows/reconcile.yaml).
#
# `terraform query` reads *.tfquery.hcl from the working directory, so this file
# is copied into the customer directory at run time rather than duplicated into
# every customer directory in the repository.
#
# Each `list` block enumerates every resource of that type in the tenant using
# the provider's list resources — a Terraform 1.14 feature that reads existing
# infrastructure whether or not it is in state. This is the same capability that
# powers jamformer's ability to generate HCL from an existing environment.
#
# Scope: every list resource the provider supports, EXCEPT
#   - jamfprotect_user             — human and IdP-provisioned accounts,
#                                    including the tenant creator, are
#                                    legitimately created outside Terraform.
#                                    Querying them produces only false
#                                    positives.
#   - jamfprotect_analytic_managed — the Jamf-provided analytic catalogue. Every
#                                    entry is a built-in and none is ever in
#                                    state, so it carries no reconciliation
#                                    value.
#
# `exclude_builtins = true` opts in to filtering Jamf-provided built-in and
# system instances — the Default plan, Full Admin and Read Only roles, and so
# on. The provider returns everything by default, so it is set on every type
# that has built-ins. Types without built-ins (api_client, custom_prevent_list,
# removable_storage_control_set, telemetry, unified_logging_filter) are queried
# as-is. It goes inside a nested `config {}` block, which is what
# `terraform query` requires.
#
# Note this is Jamf Protect only because that is what this pipeline manages. The
# same shape works for any provider with list resources — point it at Jamf Pro
# blueprints, policies, scripts or profiles and nothing else about the workflow
# changes.
# -----------------------------------------------------------------------------

list "jamfprotect_plan" "all" {
  provider = jamfprotect
  config {
    exclude_builtins = true
  }
}

list "jamfprotect_analytic" "all" {
  provider = jamfprotect
  config {
    exclude_builtins = true
  }
}

list "jamfprotect_analytic_set" "all" {
  provider = jamfprotect
  config {
    exclude_builtins = true
  }
}

list "jamfprotect_exception_set" "all" {
  provider = jamfprotect
  config {
    exclude_builtins = true
  }
}

list "jamfprotect_role" "all" {
  provider = jamfprotect
  config {
    exclude_builtins = true
  }
}

list "jamfprotect_action_configuration" "all" {
  provider = jamfprotect
  config {
    exclude_builtins = true
  }
}

list "jamfprotect_group" "all" {
  provider = jamfprotect
  config {
    exclude_builtins = true
  }
}

list "jamfprotect_api_client" "all" {
  provider = jamfprotect
}

list "jamfprotect_custom_prevent_list" "all" {
  provider = jamfprotect
}

list "jamfprotect_removable_storage_control_set" "all" {
  provider = jamfprotect
}

list "jamfprotect_telemetry" "all" {
  provider = jamfprotect
}

list "jamfprotect_unified_logging_filter" "all" {
  provider = jamfprotect
}
