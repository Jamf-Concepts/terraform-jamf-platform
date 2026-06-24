// Full policy exercising all major transforms.
resource "jamfplatform_pro_policy" "full" {





  general = {
    name                          = "tf-localtest-policy-template-001"
    enabled                       = false
    trigger_checkin               = false
    trigger_enrollment_complete   = false
    trigger_login                 = false
    trigger_network_state_changed = false
    trigger_startup               = false
    trigger_other                 = "EVENT"
    frequency                     = "Once per computer"
    offline                       = false
    category_id                   = -1
    site_id                       = -1
  }
  scope = {
    targets = {
      all_computers      = false
      computer_ids       = [16, 20, 21]
      computer_group_ids = [78, 1]
    }
    exclusions = {
      computer_ids       = [16]
      computer_group_ids = [118]
    }
  }
  self_service = {
    use_for_self_service      = true
    self_service_display_name = ""
    install_button_text       = "Install"
    self_service_description  = ""
    feature_on_main_page      = false
    notification              = false
    notification_subject      = "Install Firefox"
    notification_message      = "This is a message for the Firefox install"
    categories = [
      {
        id         = 1
        display_in = true
        feature_in = false
      },
    ]
  }
  packages = {
    distribution_point = "default"
    packages = [
      {
        id     = 123
        action = "Install"
      },
    ]
  }
  scripts = {
    scripts = [
      {
        id         = 123
        priority   = "After"
        parameter4 = "param_value_4"
        parameter5 = "param_value_5"
      },
    ]
  }
  disk_encryption = {
    action                           = "apply"
    disk_encryption_configuration_id = 1
    auth_restart                     = false
  }
  printers = {
    printers = [
      {
        id           = 1
        name         = "Printer1"
        action       = "install"
        make_default = true
      },
    ]
  }
  dock_items = {
    dock_items = [
      {
        id     = 1
        name   = "Safari"
        action = "Add To End"
      },
    ]
  }
  local_accounts = [
    {
      action              = "Create"
      username            = "newuser"
      password            = "password123"
      admin               = true
      password_wo_version = 1
    },
  ]
  management_account = {
    action                      = "rotate"
    managed_password            = "newmanagedpassword"
    managed_password_length     = 15
    managed_password_wo_version = 1
  }
  efi_password = {
    of_mode                = "command"
    of_password            = "firmwarepassword"
    of_password_wo_version = 1
  }
  restart_options = {
    message              = "This computer will restart in 5 minutes."
    specify_startup      = "Standard Restart"
    minutes_until_reboot = 5
  }
  maintenance = {
    recon                       = true
    reset_name                  = false
    install_all_cached_packages = false
  }
  files_and_processes = {
    search_by_path = "/Applications/SomeApp.app"
    delete_file    = true
    run_command    = "echo 'Hello, World!'"
  }
  user_interaction = {
    message_start  = "Policy is about to run."
    message_finish = "Policy has completed."
  }
}
