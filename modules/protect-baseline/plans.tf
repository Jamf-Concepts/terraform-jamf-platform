# -----------------------------------------------------------------------------
# Plans — Managed Protect
# -----------------------------------------------------------------------------
# Standard customers get one plan (threat prevention only).
#
# Enhanced customers get two plans:
#   1. Managed Protect - Threat Prevention              — threat prevention only,
#      assigned to computers excluded from USB controls via the Jamf Protect EA
#   2. Managed Protect - Threat Prevention and Device Controls — threat prevention
#      plus the removable storage control set, assigned to all other managed computers
#
# Both plans share identical configuration except name and whether the
# removable_storage_control_set is attached. The two-plan design exists so a
# single customer can hold a small carve-out of machines exempt from device
# controls without weakening the control set itself.
#
# Plan scoping (which computers land on which plan) is done in Jamf Pro via
# smart groups against the Jamf Protect extension attribute, not here.
# -----------------------------------------------------------------------------

# --- Standard plan (all tiers) ----------------------------------------------

resource "jamfprotect_plan" "managed_protect_standard" {
  name = "Managed Protect - Threat Prevention"

  action_configuration       = jamfprotect_action_configuration.managed_protect_standard.id
  advanced_threat_controls   = "Disable"
  tamper_prevention          = "Block and report"
  endpoint_threat_prevention = "Block and report"
  auto_update                = true
  communications_protocol    = "MQTT:443"
  log_level                  = "Error"

  analytic_sets = [
    jamfprotect_analytic_set.managed_protect_standard.id,
  ]

  # Order matters less than completeness here: the Jamf-managed defaults, the
  # exclusions every customer gets, then anything specific to this customer.
  exception_sets = concat(
    [local.jamf_managed_default_exceptions_id],
    [jamfprotect_exception_set.global_exclusions.id],
    [for k, v in jamfprotect_exception_set.customer : v.id],
  )

  removable_storage_control_set = null
  telemetry                     = local.enable_telemetry ? jamfprotect_telemetry.managed_protect_telemetry[0].id : null

  compliance_baseline_reporting = false
  reporting_interval            = 1440

  # Computer Check-in Information — Select All
  report_architecture  = true
  report_hostname      = true
  report_memory_size   = true
  report_model_name    = true
  report_serial_number = true
}

# --- Enhanced plan (enhanced tier only) -------------------------------------
#
# `count` on a tier flag is the conditional-resource pattern: standard-tier
# customers simply never create this resource, and Terraform reports nothing
# to do for it rather than needing a separate module or workspace shape.

resource "jamfprotect_plan" "managed_protect_enhanced" {
  count = local.enable_device_controls ? 1 : 0

  name = "Managed Protect - Threat Prevention and Device Controls"

  action_configuration       = jamfprotect_action_configuration.managed_protect_standard.id
  advanced_threat_controls   = "Disable"
  tamper_prevention          = "Block and report"
  endpoint_threat_prevention = "Block and report"
  auto_update                = true
  communications_protocol    = "MQTT:443"
  log_level                  = "Error"

  analytic_sets = [
    jamfprotect_analytic_set.managed_protect_standard.id,
  ]

  exception_sets = concat(
    [local.jamf_managed_default_exceptions_id],
    [jamfprotect_exception_set.global_exclusions.id],
    [for k, v in jamfprotect_exception_set.customer : v.id],
  )

  removable_storage_control_set = jamfprotect_removable_storage_control_set.managed_protect_enhanced[0].id
  telemetry                     = local.enable_telemetry ? jamfprotect_telemetry.managed_protect_telemetry[0].id : null

  compliance_baseline_reporting = false
  reporting_interval            = 1440

  # Computer Check-in Information — Select All
  report_architecture  = true
  report_hostname      = true
  report_memory_size   = true
  report_model_name    = true
  report_serial_number = true
}
