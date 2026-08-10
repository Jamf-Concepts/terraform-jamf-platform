## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.26.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Target every managed Mac. Compliance Benchmarks Engine handles branching by
## OS version internally (selected_os_versions omitted = every version the
## baseline supports), so unlike the classic-API module this doesn't need a
## smart group per OS version.
resource "jamfplatform_device_group" "all_macs_cis_lvl1" {
  name        = "CIS Level 1 - All Managed Macs"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Computer Group"
      operator = "member of"
      value    = "All Managed Clients"
    },
  ]
}

data "jamfplatform_cbengine_rules" "cis_lvl1" {
  baseline_id = "cis_lvl1"
}

resource "jamfplatform_cbengine_benchmark" "cis_lvl1" {
  title              = "CIS Level 1 Benchmark - macOS"
  description        = "Deployed by the Jamf Foundations onboarder via the Compliance Benchmarks Engine."
  source_baseline_id = "cis_lvl1"

  rules = [
    for r in data.jamfplatform_cbengine_rules.cis_lvl1.rules : {
      id      = r.id
      enabled = r.enabled
    }
  ]

  # selected_os_versions omitted — targets every OS version the baseline supports.

  target_device_groups = [jamfplatform_device_group.all_macs_cis_lvl1.id]
  enforcement_mode     = "MONITOR_AND_ENFORCE"
}
