# -----------------------------------------------------------------------------
# Action Configuration: Managed Protect
# -----------------------------------------------------------------------------
# Where alerts go and how much detail travels with them.
#
# Collects High, Medium, Low and Informational alerts into the Jamf Protect cloud
# with no additional data attributes. All twelve *_included_data_attributes sets
# are required by the provider, so an empty set is how you say "no enrichment".
# Populate them per the resource documentation if you need richer alerts.
#
# Telemetry log collection is attached only when the customer has opted in.
# -----------------------------------------------------------------------------

resource "jamfprotect_action_configuration" "managed_protect_standard" {
  name = "Managed Protect - Standard"

  alert_data_collection = {
    binary_included_data_attributes                = []
    download_event_included_data_attributes        = []
    file_included_data_attributes                  = []
    file_system_event_included_data_attributes     = []
    gatekeeper_event_included_data_attributes      = []
    group_included_data_attributes                 = []
    keylog_register_event_included_data_attributes = []
    process_event_included_data_attributes         = []
    process_included_data_attributes               = []
    screenshot_event_included_data_attributes      = []
    synthetic_click_event_included_data_attributes = []
    user_included_data_attributes                  = []
  }

  jamf_protect_cloud_endpoint = {
    collect_alerts = ["high", "medium", "low", "informational"]
    collect_logs   = local.enable_telemetry ? ["telemetry"] : []
  }
}
