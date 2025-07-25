## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Create Categories
resource "jamfpro_category" "category_admin_tools" {
  name     = "Admin Tools"
  priority = 9
}

## Create Smart Group
resource "jamfpro_smart_computer_group" "group_apple_silicon" {
  name = "Apple Silicon Macs"
  criteria {
    name        = "Apple Silicon"
    search_type = "is"
    value       = "Yes"
    and_or      = "and"
    priority    = 0
  }
}

## Create Policy
resource "jamfpro_policy" "policy_rosetta_2" {
  name            = "Rosetta 2 Install"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.category_admin_tools.id


  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_apple_silicon.id]
  }

  self_service {
    use_for_self_service            = false
    self_service_display_name       = ""
    install_button_text             = ""
    self_service_description        = ""
    force_users_to_view_description = false
    feature_on_main_page            = false
  }

  payloads {
    files_processes {
      search_by_path         = ""
      delete_file            = false
      locate_file            = ""
      update_locate_database = false
      spotlight_search       = ""
      search_for_process     = ""
      kill_process           = false
      run_command            = "/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
    }

    maintenance {
      recon                       = true
      reset_name                  = false
      install_all_cached_packages = false
      heal                        = false
      prebindings                 = false
      permissions                 = false
      byhost                      = false
      system_cache                = false
      user_cache                  = false
      verify                      = false
    }
  }
}
