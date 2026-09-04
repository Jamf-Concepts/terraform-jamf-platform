# -----------------------------------------------------------------------------
# Customer Configuration: <CUSTOMER_NAME>
# -----------------------------------------------------------------------------
# The only file that meaningfully differs between customers. Everything here is
# non-secret by design and is committed, reviewed in a pull request, and
# versioned. Credentials never appear in this file. They reach Terraform as
# TF_VAR_* environment variables from GitHub Environment secrets.
#
# Terraform loads *.auto.tfvars automatically, so there is no -var-file flag to
# remember in the workflows.
#
# Everything below is commented out. An uncommented tier and nothing else is a
# complete, valid customer.
# -----------------------------------------------------------------------------

# --- Product Tier -----------------------------------------------------------
# "standard": threat prevention only
# "enhanced": threat prevention plus removable storage device controls

product_tier = "standard"

# --- Device Controls (optional) ---------------------------------------------
# Enhanced tier only. Default is "Prevent", so removable storage is blocked unless
# an override below says otherwise. Only relax this with a documented reason.
#
# removable_storage_default_permission = "Read Only"

# --- Removable Storage Overrides (optional) ---------------------------------
# Enhanced tier only. Four ways to identify a device; use the narrowest one
# that solves the problem. A serial number override covers one physical device;
# a vendor ID override covers everything that vendor has ever made.
#
# Valid permissions: "Prevent", "Read Only", "Read and Write"
#
# removable_storage_override_vendor_id = [
#   {
#     vendor_ids = ["0x154b"]
#     permission = "Read and Write"
#   }
# ]
#
# removable_storage_override_product_id = [
#   {
#     permission = "Read and Write"
#     product_id = [
#       {
#         vendor_id  = "0x0781"
#         product_id = "0x5583"
#       }
#     ]
#   }
# ]
#
# removable_storage_override_serial_number = [
#   {
#     serial_numbers = ["EXAMPLE123456"]
#     permission     = "Read and Write"
#   }
# ]
#
# removable_storage_override_encrypted_devices = [
#   {
#     permission = "Read and Write"
#   }
# ]

# --- Exception Sets (optional) ----------------------------------------------
# Threat prevention exclusions specific to this customer. The map key becomes
# the exception set name in the console, so name it after the application or
# the reason, not after the customer.
#
# exception_sets = {
#   "line-of-business-app" = {
#     processes = ["/Applications/Example.app/Contents/MacOS/Example"]
#     paths     = ["/Library/Application Support/Example"]
#   }
# }

# --- Telemetry (optional) ---------------------------------------------------
# Endpoint telemetry collection. Off by default: telemetry has a volume cost
# wherever it lands.
#
# enable_telemetry = true

# --- Microsoft Sentinel Data Forwarding (optional) --------------------------
# Populated by scripts/enable-data-forwarding.sh rather than by hand.
#
# The application secret is NOT stored here: it lives in the customer's
# GitHub Environment as SENTINEL_APP_SECRET. It is a write-only value that
# Terraform cannot read back, so rotating it means BOTH updating the secret in
# GitHub AND incrementing app_secret_version below. The version bump is the
# only thing that tells Terraform anything changed.
#
# sentinel = {
#   directory_id             = "<azure-tenant-id>"
#   application_id           = "<app-registration-client-id>"
#   data_collection_endpoint = "https://<endpoint>.ingest.monitor.azure.com"
#   alerts_rule_id           = "<dcr-immutable-id-for-alerts>"
#   alerts_stream_name       = "<stream-name-for-alerts>"
#   telemetry_rule_id        = "<dcr-immutable-id-for-telemetry>"
#   telemetry_stream_name    = "<stream-name-for-telemetry>"
#   app_secret_version       = "1"
# }
