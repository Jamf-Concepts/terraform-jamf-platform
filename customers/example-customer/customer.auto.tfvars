# -----------------------------------------------------------------------------
# Customer Configuration: example-customer
# -----------------------------------------------------------------------------
# A worked example. Compare it with customers/_template/customer.auto.tfvars
# (everything commented out, the minimum viable customer) and with
# customers/staging (a plain standard-tier workspace).
#
# This customer is on the enhanced tier and has ordered three things off the
# menu: one USB device exception, one threat prevention exception set, and
# telemetry. Every one of them is a value in this file. No code was changed to
# accommodate them, and nothing was clicked in the console.
#
# Delete this directory before you onboard anyone real. It exists to be read.
# -----------------------------------------------------------------------------

# --- Product Tier -----------------------------------------------------------
# Enhanced: threat prevention plus removable storage device controls. Creates a
# second plan and the control set (see plans.tf and device_controls.tf).

product_tier = "enhanced"

# --- Removable Storage Overrides --------------------------------------------
# The default permission stays "Prevent". This is one carve-out, not a relaxed
# baseline. A serial number override is the narrowest form available: it covers
# exactly this physical device, and nothing else the vendor makes.
#
# The reason for an exception belongs in the pull request that adds it, and the
# request should have an expiry. An exception nobody revisits is how a control
# set quietly stops being a control.

removable_storage_override_serial_number = [
  {
    serial_numbers             = ["EXAMPLE123456"]
    permission                 = "Read and Write"
    local_notification_message = "Approved device. See change request."
  }
]

# --- Exception Sets ---------------------------------------------------------
# A line-of-business application that trips threat prevention. Named after the
# application rather than the customer, so a reviewer can tell what it is for.
#
# The module turns each list into the provider's rule structure: `processes`
# become Process Event / Process Path rules, `paths` become File System Event /
# File Path rules. See modules/protect-baseline/exception_sets.tf.

exception_sets = {
  "line-of-business-app" = {
    processes = ["/Applications/Example.app/Contents/MacOS/Example"]
    paths     = ["/Library/Application Support/Example"]
  }
}

# --- Telemetry --------------------------------------------------------------
# Creates the telemetry configuration and attaches it to both plans. Telemetry
# has a volume cost wherever it lands, so it is opt-in rather than baseline.

enable_telemetry = true

# --- Microsoft Sentinel Data Forwarding -------------------------------------
# Not enabled for this customer. Run scripts/enable-data-forwarding.sh to add
# it. The script prompts for the Azure values, stores the secret in this
# customer's GitHub Environment, writes the block into this file and opens a
# pull request. See customers/_template/customer.auto.tfvars for the shape.
