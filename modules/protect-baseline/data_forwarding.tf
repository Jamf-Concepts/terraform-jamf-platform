# -----------------------------------------------------------------------------
# SIEM Data Forwarding
# -----------------------------------------------------------------------------
# Forwards alerts and telemetry to an external SIEM. Opt-in per customer, created
# only when a destination is configured (see locals in main.tf).
#
# Wired for Microsoft Sentinel. The Amazon S3 block is present but disabled so the
# resource shape matches what the provider expects and enabling S3 later is an
# edit rather than an addition.
#
# The application secret is write-only: sent to the API, never read back into
# state. Rotation needs a version bump as well as a new value, because the version
# number is the only thing Terraform can compare. See app_secret_version in the
# customer's tfvars.
#
# depends_on: plans must exist first, or there is no data source to forward from.
# -----------------------------------------------------------------------------

resource "jamfprotect_data_forwarding" "managed_protect_data_forwarding" {
  count = local.enable_data_forwarding ? 1 : 0

  microsoft_sentinel = {
    enabled                             = true
    directory_id                        = var.sentinel.directory_id
    application_id                      = var.sentinel.application_id
    data_collection_endpoint            = var.sentinel.data_collection_endpoint
    application_secret_value_wo         = var.sentinel_app_secret
    application_secret_value_wo_version = var.sentinel.app_secret_version

    alerts = {
      enabled                           = true
      data_collection_rule_immutable_id = var.sentinel.alerts_rule_id
      stream_name                       = var.sentinel.alerts_stream_name
    }

    unified_logs = {
      enabled = false
    }

    # Superseded by the `telemetry` block below. Kept disabled rather than
    # removed because the provider still expects the attribute.
    telemetry_deprecated = {
      enabled = false
    }

    telemetry = {
      enabled                           = true
      data_collection_rule_immutable_id = var.sentinel.telemetry_rule_id
      stream_name                       = var.sentinel.telemetry_stream_name
    }
  }

  amazon_s3 = {
    enabled     = false
    bucket_name = ""
    prefix      = ""
    iam_role    = ""
  }

  depends_on = [
    jamfprotect_plan.managed_protect_standard,
    jamfprotect_plan.managed_protect_enhanced,
  ]

  lifecycle {
    # Data forwarding is a customer's audit trail into their own SIEM.
    # prevent_destroy turns an accidental removal into a failed plan a human has
    # to unblock, rather than a silent gap in their logging.
    prevent_destroy = true

    precondition {
      condition     = var.sentinel_app_secret != ""
      error_message = "sentinel_app_secret must be set when sentinel data forwarding is configured."
    }
  }
}
