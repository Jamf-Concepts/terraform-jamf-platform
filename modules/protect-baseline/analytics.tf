# -----------------------------------------------------------------------------
# Analytics — Custom Analytic & Analytic Set
# -----------------------------------------------------------------------------
# The custom analytic below watches the Protect quarantine directory and tags the
# machine in Jamf Pro via a smart group, so a quarantine event becomes something
# you can scope policies against.
# -----------------------------------------------------------------------------

# --- Custom Analytic: Managed Protect Quarantine ----------------------------

resource "jamfprotect_analytic" "managed_protect_quarantine" {
  name        = "Managed Protect Quarantine"
  description = "Detected new item added to Jamf Protect Quarantine directory"
  sensor_type = "File System Event"
  severity    = "Informational"
  level       = 0

  # Event types 0, 3 and 7 are create / rename / clone. The path pattern matches
  # any file written one level inside a UUID-named quarantine folder.
  filter = "$event.type IN {0, 3, 7} AND $event.path MATCHES[c] \"/Library/Application Support/JamfProtect/Quarantine/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+\""

  categories     = ["Known Malicious File"]
  context_item   = []
  tags           = []
  snapshot_files = []

  # Creates a Jamf Pro smart group membership signal for this analytic, so the
  # detection is actionable in Pro without a second integration.
  add_to_jamf_pro_smart_group     = true
  jamf_pro_smart_group_identifier = "managed-protect-quarantine"
}

# --- Analytic Set: Managed Protect Standard ---------------------------------
# Analytic sets are what plans attach to, so even a single custom analytic
# needs a set to wrap it.

resource "jamfprotect_analytic_set" "managed_protect_standard" {
  name = "Managed Protect - Standard"
  analytics = [
    jamfprotect_analytic.managed_protect_quarantine.id,
  ]
}
