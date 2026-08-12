resource "jamfplatform_pro_policy" "run_hello_world" {
  general = {
    name            = "Run Hello World"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.engineering.id
  }

  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.test_machines.jamf_pro_id]
    }
  }

  scripts = {
    scripts = [
      {
        id       = jamfplatform_pro_script.hello_world.id
        priority = "After"
      }
    ]
  }

  maintenance = {
    update_inventory = true
  }
}
