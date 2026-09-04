# -----------------------------------------------------------------------------
# Device Controls: Removable Storage
# -----------------------------------------------------------------------------
# Enhanced tier only.
#
# The default permission is "Prevent": removable storage is blocked unless an
# override says otherwise. Start closed, open deliberately, and open it in code so
# the exception is reviewed and survives the next apply.
#
# Per-customer exceptions arrive through the four removable_storage_override_*
# variables. Anything added in the console instead is reported by drift detection
# and reverted on remediation.
# -----------------------------------------------------------------------------

resource "jamfprotect_removable_storage_control_set" "managed_protect_enhanced" {
  count = local.enable_device_controls ? 1 : 0

  name                               = "Managed Protect - Enhanced"
  default_permission                 = var.removable_storage_default_permission
  default_local_notification_message = "This removable storage device is not allowed."

  # Per-customer overrides, passed through from variables as nested attributes.
  override_vendor_id         = var.removable_storage_override_vendor_id
  override_product_id        = var.removable_storage_override_product_id
  override_serial_number     = var.removable_storage_override_serial_number
  override_encrypted_devices = var.removable_storage_override_encrypted_devices
}
