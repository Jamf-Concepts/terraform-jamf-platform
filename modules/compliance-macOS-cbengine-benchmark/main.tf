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
## baseline supports), so unlike the classic-API modules this doesn't need a
## smart group per OS version.
resource "jamfplatform_device_group" "all_macs_cbengine_benchmark" {
  name        = "${var.benchmark_title} - All Managed Macs"
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

data "jamfplatform_cbengine_rules" "benchmark" {
  baseline_id = var.baseline_id
}

resource "jamfplatform_cbengine_benchmark" "benchmark" {
  title              = "${var.benchmark_title} - macOS"
  description        = "Deployed by the Jamf Foundations onboarder via the Compliance Benchmarks Engine."
  source_baseline_id = var.baseline_id

  rules = [
    for r in data.jamfplatform_cbengine_rules.benchmark.rules : {
      id      = r.id
      enabled = r.enabled
    }
  ]

  # selected_os_versions omitted — targets every OS version the baseline supports.

  target_device_groups = [jamfplatform_device_group.all_macs_cbengine_benchmark.id]
  enforcement_mode     = "MONITOR_AND_ENFORCE"
}
