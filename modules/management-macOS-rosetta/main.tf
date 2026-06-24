## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create Categories
resource "jamfplatform_pro_category" "category_admin_tools" {
  name     = "Admin Tools"
  priority = 9
}

## Create Smart Group
resource "jamfplatform_device_group" "group_apple_silicon" {
  name        = "Apple Silicon Macs"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Apple Silicon"
      operator = "is"
      value    = "Yes"
    },
  ]
}

## Create Policy
resource "jamfplatform_pro_policy" "policy_rosetta_2" {




  general = {
    name            = "Rosetta 2 Install"
    enabled         = true
    trigger_checkin = true
    frequency       = "Once per computer"
    category_id     = jamfplatform_pro_category.category_admin_tools.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_apple_silicon.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service            = false
    self_service_display_name       = ""
    install_button_text             = ""
    self_service_description        = ""
    force_users_to_view_description = false
    feature_on_main_page            = false
  }
  files_and_processes = {
    search_by_path         = ""
    delete_file            = false
    locate_file            = ""
    update_locate_database = false
    spotlight_search       = ""
    search_for_process     = ""
    kill_process           = false
    run_command            = "/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
  }
  maintenance = {
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
