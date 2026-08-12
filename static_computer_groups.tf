resource "jamfplatform_device_group" "test_machines" {
  name        = "Test Machines"
  group_type  = "static"
  device_type = "computer"
}