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
# Every flag is set explicitly. The provider declares no defaults for them, so
# anything left out is decided by the server rather than by this file.
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

  # Collect inbound and outbound network connections. Requires Jamf Protect agent
  # 8.14.0+, macOS 26+, and the Network Content Filter Profile deployed first, so
  # it is off here rather than silently failing the prerequisites.
  log_network = false

  # Custom log file paths, on top of the event sources above. Required by the
  # provider, so an empty set is how you say "none".
  log_file_path = []

  file_hashes                          = false
  collect_performance_metrics          = false
  collect_diagnostic_and_crash_reports = false
}
