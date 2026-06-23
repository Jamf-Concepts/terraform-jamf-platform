## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create Categories
resource "jamfplatform_pro_category" "category_disk_encrpytion" {
  name     = "Disk Encryption"
  priority = 9
}

## Create scripts
resource "jamfplatform_pro_script" "script_reissuekey" {
  name            = "Reissue FileVault 2 Key"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/reissuekey.sh")
  category_id     = jamfplatform_pro_category.category_disk_encrpytion.id
  info            = "Source: https://github.com/jamf/FileVault2_Scripts/blob/master/reissueKey.sh"
}

## Create Smart Computer Groups - Scoping
resource "jamfplatform_device_group" "group_invalid_recovery_key" {
  name = "Invalid FileVault 2 Recovery Key"
  group_type  = "smart"
  device_type = "computer"

  criteria = [
    {
      criteria = "FileVault 2 Partition Encryption State"
      operator = "is"
      value    = "Encrypted"
    },
    {
      and_or   = "and"
      criteria = "FileVault 2 Individual Key Validation"
      operator = "is not"
      value    = "Valid"
    },
  ]
}

resource "jamfplatform_device_group" "group_disk_encrypted" {
  name = "* FileVault 2 Enabled"
  group_type  = "smart"
  device_type = "computer"

  criteria = [
    {
      criteria = "FileVault 2 Partition Encryption State"
      operator = "is"
      value    = "Encrypted"
    },
  ]
}

## Create policies
resource "jamfplatform_pro_policy" "policy_reissue_recovery_key" {
  name          = "Reissue FileVault 2 Recovery Key"
  enabled       = true
  trigger_other = ""
  frequency     = "Ongoing"
  category_id   = jamfplatform_pro_category.category_disk_encrpytion.id


  scope {
    all_computers      = false
    computer_group_ids = [jamfplatform_device_group.group_invalid_recovery_key.jamf_pro_id]
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
      id         = jamfplatform_pro_script.script_reissuekey.id
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

resource "jamfplatform_pro_macos_configuration_profile" "jamfplatform_pro_macos_configuration_profile_enablefv" {
  general = {
    name                = "Enable FileVault 2"
    description         = "This configuration profile enforces FileVault 2 encryption. Prompts at next login"
    level               = "System"
    category_id         = jamfplatform_pro_category.category_disk_encrpytion.id
    redeploy_on_update  = "Newly Assigned"
    distribution_method = "Install Automatically"
    payloads            = file("${path.module}/support_files/enablefilevault.mobileconfig")
    user_removable      = false
  }

  scope = {
    targets = {
      all_computers = false
    }
  }
}
