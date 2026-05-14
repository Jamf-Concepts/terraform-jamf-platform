# Step 1 — add your device group here
resource "jamfplatform_device_group" "test_machines" {
  name        = "Test Machines"
  description = "Managed by Terraform"
  group_type  = "smart"
  device_type = "computer"

  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than or equal"
      value    = "14.0"
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "is"
      value    = "C02XY1ZTEST"
    }
  ]
}
