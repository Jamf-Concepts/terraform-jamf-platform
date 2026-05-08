# https://learn.jamf.com/en-US/bundle/jamf-compliance-benchmarks-configuration-guide/page/Compliance_Benchmarks_Configuration_Guide.html
#
# The data source reads the current CIS Level 1 rule set from Jamf Platform.
# The for expressions in sources and rules copy every rule from the baseline
# into the benchmark resource — new rules added upstream are picked up
# automatically on the next apply.
#
# enforcement_mode = "MONITOR" reports compliance without remediating.
# Change to "MONITOR_AND_ENFORCE" to enable automatic remediation.

data "jamfplatform_cbengine_rules" "cis_lvl1" {
  baseline_id = "cis_lvl1"
}

data "jamfpro_group" "desktops" {
  group_jamfpro_id = jamfpro_smart_computer_group_v2.model["desktops"].id
  group_type       = "COMPUTER"
}

# This benchmark scopes to the desktops smart group only. Laptops can have
# their own benchmark resource with different rule overrides if needed —
# copy this block, change the title, and point target_device_group at the
# laptops group data source.
resource "jamfplatform_cbengine_benchmark" "cis_lvl1_all" {
  title              = "CIS Level 1 - All Desktops"
  description        = "Managed by Terraform"
  source_baseline_id = "cis_lvl1"
  sources = [
    for s in data.jamfplatform_cbengine_rules.cis_lvl1.sources : {
      branch   = s.branch
      revision = s.revision
    }
  ]
  rules = [
    for r in data.jamfplatform_cbengine_rules.cis_lvl1.rules : {
      id      = r.id
      enabled = r.enabled
    }
  ]
  target_device_group = data.jamfpro_group.desktops.group_platform_id
  enforcement_mode    = "MONITOR"
}
