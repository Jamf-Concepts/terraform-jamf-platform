## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.5"
    }
  }
}

##Computer Inventory Collection Settings
resource "jamfpro_computer_inventory_collection" "example" {
  local_user_accounts               = true
  home_directory_sizes              = true
  hidden_accounts                   = true
  printers                          = true
  active_services                   = true
  mobile_device_app_purchasing_info = true
  computer_location_information     = true
  package_receipts                  = true
  available_software_updates        = true
  include_applications              = true
  include_fonts                     = true
  include_plugins                   = true

  applications {
    path     = "/Applications/ExampleApp.app"
    platform = "macOS"
  }

  applications {
    path     = "/Applications/AnotherApp.app"
    platform = "macOS"
  }

  fonts {
    path     = "/Library/Fonts/ExampleFont.ttf"
    platform = "macOS"
  }

  fonts {
    path     = "/Library/Fonts/AnotherFont.ttf"
    platform = "macOS"
  }

  plugins {
    path     = "/Library/Internet Plug-Ins/ExamplePlugin.plugin"
    platform = "macOS"
  }

  plugins {
    path     = "/Library/Internet Plug-Ins/AnotherPlugin.plugin"
    platform = "macOS"
  }
}

##Computer Check-in Settings
resource "jamfpro_client_checkin" "jamfpro_client_checkin" {
  check_in_frequency    = 15
  create_startup_script = true
  //log_startup_event                  = true
  //ensure_ssh_is_enabled              = false
  //check_for_policies_at_startup      = true
  //create_login_logout_hooks          = true
  //log_username                       = true
  //check_for_policies_at_login_logout = true
}
