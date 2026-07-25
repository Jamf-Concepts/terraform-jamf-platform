resource "jamfplatform_blueprints_blueprint" "test_blueprint" {
  name          = "Software Update Test Blueprint"
  description   = "This is a test blueprint for software updates."
  deployed      = true
  device_groups = [jamfplatform_device_group.computers_nudge_is_installed.id]

  component_blocks = [
    {
      name = "Software Update Test Blueprint"
      software_update = {
        enforce_after_days    = 7
        ignore_major_versions = true
        deployment_time       = "15:00"
      }
    },
  ]
}
