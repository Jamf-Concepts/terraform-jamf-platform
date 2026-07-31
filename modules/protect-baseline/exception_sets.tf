# -----------------------------------------------------------------------------
# Exception Sets
# -----------------------------------------------------------------------------
# Three kinds of exception set feed every plan:
#
# 1. Jamf Managed Default Exceptions, pre-existing in every tenant. Read via
#    data source, so plans reference its ID without an import block or a
#    hardcoded UUID that differs per tenant.
#
# 2. Global exclusions, defined once here and applied to everyone. A false
#    positive confirmed across the fleet goes here and is fixed everywhere on
#    the next apply.
#
# 3. Per-customer exception sets, built from the exception_sets variable. A
#    customer asks for an exclusion, it goes in their tfvars, it gets reviewed.
# -----------------------------------------------------------------------------

# --- Jamf Managed Default Exceptions (data source) --------------------------
#
# A data source reads existing infrastructure rather than creating it. `one()`
# returns the single element of a list and errors on zero or many. That hard
# failure is deliberate: a silent `null` here would push a plan with no default
# exceptions attached.

data "jamfprotect_exception_sets" "all" {}

locals {
  jamf_managed_default_exceptions_id = one([
    for e in data.jamfprotect_exception_sets.all.exception_sets :
    e.uuid if e.name == "Jamf Managed Default Exceptions" && e.managed == true
  ])
}

# --- Global Exclusions ------------------------------------------------------
# Baseline exclusions applied to every customer on every tier. Keep it short and
# evidenced: each entry should be a confirmed false positive, not a convenience.
# Record why next to it.

resource "jamfprotect_exception_set" "global_exclusions" {
  name = "Managed Protect - Global Exclusions"

  exceptions = [
    {
      type = "File System Event"
      rules = [
        {
          # Docker Desktop rewrites this launch daemon on every start, which
          # trips file system event monitoring on developer machines.
          rule_type = "File Path"
          value     = "/Library/LaunchDaemons/com.docker.socket.plist"
        },
      ]
    },
  ]
}

# --- Per-Customer Exception Sets (dynamic) ----------------------------------
#
# The dynamic-resource pattern: `for_each` over a map supplied in the
# customer's tfvars. One customer with four exception sets and another with
# none both use this identical block. The module flexes, the code does not
# fork.
#
# Each entry's key becomes the exception set name in the console, so name them
# so a reviewer can tell what they are for at a glance.

resource "jamfprotect_exception_set" "customer" {
  for_each = var.exception_sets

  name = each.key
  exceptions = concat(
    # Process Event exceptions
    length(each.value.processes) > 0 ? [
      {
        type = "Process Event"
        rules = [
          for process in each.value.processes : {
            rule_type = "Process Path"
            value     = process
          }
        ]
      }
    ] : [],
    # File System Event exceptions
    length(each.value.paths) > 0 ? [
      {
        type = "File System Event"
        rules = [
          for path in each.value.paths : {
            rule_type = "File Path"
            value     = path
          }
        ]
      }
    ] : [],
  )
}
