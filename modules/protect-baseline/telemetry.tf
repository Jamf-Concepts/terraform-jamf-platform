# -----------------------------------------------------------------------------
# Telemetry — Managed Protect Telemetry
# -----------------------------------------------------------------------------
# Endpoint telemetry collection, opt-in per customer via enable_telemetry.
# Telemetry volume has a cost wherever it lands: the Protect cloud, a SIEM, or
# both.
#
# When created, the configuration ID is attached to every plan (plans.tf) and, if
# SIEM forwarding is enabled, streamed onward (data_forwarding.tf).
#
# File hashing, performance metrics and crash reports are off by default. They are
# the three settings most likely to change the volume and sensitivity of what you
# collect, so they should be a conscious decision.
# -----------------------------------------------------------------------------

resource "jamfprotect_telemetry" "managed_protect_telemetry" {
  count = local.enable_telemetry ? 1 : 0

  name        = "Managed Protect Telemetry"
  description = "Telemetry collection for Managed Protect endpoints"

  log_access_and_authentication  = true
  log_apple_security             = true
  log_applications_and_processes = true
  log_hardware_and_software      = true
  log_persistence                = true
  log_system                     = true
  log_users_and_groups           = true

  # Additional log file paths to collect. Empty means the built-in sources only.
  log_file_path = []

  file_hashes                          = false
  collect_performance_metrics          = false
  collect_diagnostic_and_crash_reports = false
}
