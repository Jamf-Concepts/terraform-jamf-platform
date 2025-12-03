## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

resource "random_integer" "entropy" {
  min = 10
  max = 999
}

## Create Categories
resource "jamfpro_category" "category_disk_encrpytion" {
  name     = "Disk Encryption [${random_integer.entropy.result}]"
  priority = 9
}

## Create scripts
resource "jamfpro_script" "script_reissuekey" {
  name            = "Reissue FileVault 2 Key [${random_integer.entropy.result}]"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/reissuekey.sh")
  category_id     = jamfpro_category.category_disk_encrpytion.id
  info            = "Source: https://github.com/jamf/FileVault2_Scripts/blob/master/reissueKey.sh"
}

## Create Smart Computer Groups - Scoping
resource "jamfpro_smart_computer_group" "group_invalid_recovery_key" {
  name = "Invalid FileVault 2 Recovery Key [${random_integer.entropy.result}]"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    search_type = "is"
    value       = "Encrypted"
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = "FileVault 2 Individual Key Validation"
    search_type = "is not"
    value       = "valid"
    and_or      = "and"
    priority    = 1
  }
}

resource "jamfpro_smart_computer_group" "group_disk_encrypted" {
  name = "* FileVault 2 Enabled [${random_integer.entropy.result}]"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    search_type = "is"
    value       = "Encrypted"
    and_or      = "and"
    priority    = 0
  }
}

## Create policies
resource "jamfpro_policy" "policy_reissue_recovery_key" {
  name          = "Reissue FileVault 2 Recovery Key [${random_integer.entropy.result}]"
  enabled       = true
  trigger_other = ""
  frequency     = "Ongoing"
  category_id   = jamfpro_category.category_disk_encrpytion.id


  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_invalid_recovery_key.id]
  }

  self_service {
    use_for_self_service            = true
    self_service_display_name       = "Get New Recovery Key"
    install_button_text             = "Fix Now"
    self_service_description        = ""
    force_users_to_view_description = false
    feature_on_main_page            = true
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_reissuekey.id
      priority   = "After"
      parameter4 = "<Replace with your organization name>"
      parameter5 = ""
      parameter6 = "<replace with additional info for the end user>"
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

resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_profile_enablefv" {
  name                = "Enable FileVault 2 [${random_integer.entropy.result}]"
  description         = "This configuration profile enforces FileVault 2 encryption. Prompts at next login"
  level               = "System"
  category_id         = jamfpro_category.category_disk_encrpytion.id
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = file("${path.module}/support_files/enablefilevault.mobileconfig")
  payload_validate    = false
  user_removable      = false

  scope {
    all_computers = false
    all_jss_users = false
  }
}
