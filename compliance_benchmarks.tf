# Step 4 — add your cbengine rules data source and output here first,
#           then replace the output with the benchmark resource once you've inspected the rules
data "jamfplatform_cbengine_rules" "cis_lvl1" {
  baseline_id = "cis_lvl1"
}

resource "jamfplatform_cbengine_benchmark" "cis_lvl1" {
  title              = "CIS Level 1"
  description        = "Managed by Terraform"
  source_baseline_id = "cis_lvl1"

  sources = [
    for s in data.jamfplatform_cbengine_rules.cis_lvl1.sources : {
      branch   = s.branch
      revision = s.revision
    }
  ]

  rules = [
    { id = "os_firewall_log_enable",                      enabled = true },
    { id = "os_gatekeeper_enable",                        enabled = true },
    { id = "system_settings_filevault_enforce",           enabled = true },
    { id = "pwpolicy_minimum_length_enforce",             enabled = true, odv_value = "15" },
    { id = "system_settings_screensaver_timeout_enforce", enabled = true, odv_value = "300" },
  ]

  target_device_group = jamfplatform_device_group.test_machines.id
  enforcement_mode    = "MONITOR"
}
