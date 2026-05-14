# Step 4 — add your cbengine rules data source and output here first,
#           then replace with the benchmark resource once you've inspected the rules
data "jamfplatform_cbengine_rules" "cis_lvl1" {
  baseline_id = "cis_lvl1"
}

output "cis_lvl1_rules" {
  value = [
    for r in data.jamfplatform_cbengine_rules.cis_lvl1.rules :
    r.odv_hint != null ? "${r.id}: ${r.title} [ODV: ${r.odv_hint}]" : "${r.id}: ${r.title}"
  ]
}
