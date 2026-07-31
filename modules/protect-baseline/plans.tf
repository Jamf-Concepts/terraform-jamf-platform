# -----------------------------------------------------------------------------
# Plans — Managed Protect
# -----------------------------------------------------------------------------
# Standard customers get one plan: threat prevention only.
#
# Enhanced customers get two, identical except for the name and whether the
# removable storage control set is attached:
#   1. Threat Prevention, for computers excluded from USB controls via the Jamf
#      Protect extension attribute
#   2. Threat Prevention and Device Controls, for everything else
#
# Two plans rather than one so a customer can hold a small carve-out of exempt
# machines without weakening the control set itself.
#
# Which computers land on which plan is scoped in Jamf Pro via smart groups
# against the Jamf Protect extension attribute, not here.
#
# Worth knowing before you change threat prevention: analytic_sets,
# advanced_threat_controls, endpoint_threat_prevention and tamper_prevention are
# ignored by the agent unless threat_prevention_strategy is "Legacy". That is the
# default and this module never sets it, so they apply. If you opt into the NGTP
# beta and switch strategy, everything below stops taking effect and you configure
# custom_engine_config instead.
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

  # Jamf-managed defaults, then the exclusions every customer gets, then anything
  # specific to this customer.
  exception_sets = concat(
    [local.jamf_managed_default_exceptions_id],
    [jamfprotect_exception_set.global_exclusions.id],
    [for k, v in jamfprotect_exception_set.customer : v.id],
  )

  removable_storage_control_set = null
  telemetry                     = local.enable_telemetry ? jamfprotect_telemetry.managed_protect_telemetry[0].id : null

  compliance_baseline_reporting = false
  reporting_interval            = 1440

  # Every non-deprecated report_* attribute. report_kernel_version and
  # report_os_version are deprecated in the provider and deliberately omitted.
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

  # As above: every non-deprecated report_* attribute.
  report_architecture  = true
  report_hostname      = true
  report_memory_size   = true
  report_model_name    = true
  report_serial_number = true
}
