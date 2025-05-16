## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Create categories
resource "jamfpro_category" "category_sonoma_cmmc_lvl1_benchmarks" {
  name     = "Sonoma - US CMMC 2.0 Level 1 Benchmarks ${var.entropy_string}"
  priority = 9
}

resource "jamfpro_category" "category_sequoia_cmmc_lvl1_benchmarks" {
  name     = "Sequoia - US CMMC 2.0 Level 1 Benchmarks ${var.entropy_string}"
  priority = 9
}

## Create scripts
resource "jamfpro_script" "script_sonoma_cmmc_lvl1_compliance" {
  name            = "Sonoma - US CMMC 2.0 Level 1 Compliance ${var.entropy_string}"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/computer_scripts/sonoma_cmmc_lvl1_compliance.sh")
  category_id     = jamfpro_category.category_sonoma_cmmc_lvl1_benchmarks.id
  info            = "This script will apply a set of rules related to the US CMMC 2.0 Level 1 benchmark for macOS Sonoma"
}

resource "jamfpro_script" "script_sequoia_cmmc_lvl1_compliance" {
  name            = "Sequoia - US CMMC 2.0 Level 1 Compliance ${var.entropy_string}"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/computer_scripts/sequoia_cmmc_lvl1_compliance.sh")
  category_id     = jamfpro_category.category_sequoia_cmmc_lvl1_benchmarks.id
  info            = "This script will apply a set of rules related to the US CMMC 2.0 Level 1 benchmark for macOS Sequoia"
}

## Create computer extension attributes
resource "jamfpro_computer_extension_attribute" "ea_cmmc_lvl1_failed_count" {
  name                   = "US CMMC 2.0 Level 1 - Failed Results Count"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "INTEGER"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsCount.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_cmmc_lvl1_failed_list" {
  name                   = "US CMMC 2.0 Level 1 - Failed Results List"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsList.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_cmmc_lvl1_version" {
  name                   = "US CMMC 2.0 Level 1 - Compliance Version"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-version.sh")
}

## Create Smart Computer Groups
resource "jamfpro_smart_computer_group" "group_sonoma_computers" {
  name = "US CMMC 2.0 Level 1 - Sonoma Computers ${var.entropy_string}"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "14."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = "Serial Number"
    search_type = "like"
    value       = "111222333444555"
    and_or      = "and"
    priority    = 1
  }
}

resource "jamfpro_smart_computer_group" "group_sonoma_cmmc_lvl1_non_compliant" {
  name = "US CMMC 2.0 Level 1 - Sonoma - Non Compliant Computers ${var.entropy_string}"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "14."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = jamfpro_computer_extension_attribute.ea_cmmc_lvl1_failed_count.name
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 1
  }
}

resource "jamfpro_smart_computer_group" "group_sequoia_computers" {
  name = "US CMMC 2.0 Level 1 - Sequoia Computers ${var.entropy_string}"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = "Serial Number"
    search_type = "like"
    value       = "111222333444555"
    and_or      = "and"
    priority    = 1
  }
}

resource "jamfpro_smart_computer_group" "group_sequoia_cmmc_lvl1_non_compliant" {
  name = "US CMMC 2.0 Level 1 - Sequoia - Non Compliant Computers ${var.entropy_string}"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = jamfpro_computer_extension_attribute.ea_cmmc_lvl1_failed_count.name
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 1
  }
}

## Create policies
resource "jamfpro_policy" "policy_sonoma_cmmc_lvl1_audit" {
  name            = "US CMMC 2.0 Level 1 - Audit (Sonoma) ${var.entropy_string}"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sonoma_cmmc_lvl1_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_computers.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sonoma_cmmc_lvl1_compliance.id
      parameter4 = "--check"
    }

    maintenance {
      recon = true
    }

    reboot {
      file_vault_2_reboot            = false
      message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
      minutes_until_reboot           = 5
      no_user_logged_in              = "Do not restart"
      start_reboot_timer_immediately = false
      startup_disk                   = "Current Startup Disk"
      user_logged_in                 = "Do not restart"
    }
  }
}

resource "jamfpro_policy" "policy_sonoma_cmmc_lvl1_remediation" {
  name            = "US CMMC 2.0 Level 1 - Remediation (Sonoma) ${var.entropy_string}"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sonoma_cmmc_lvl1_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_cmmc_lvl1_non_compliant.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sonoma_cmmc_lvl1_compliance.id
      parameter4 = "--check"
      parameter5 = "--fix"
      parameter6 = "--check"
    }

    maintenance {
      recon = true
    }

    reboot {
      file_vault_2_reboot            = false
      message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
      minutes_until_reboot           = 5
      no_user_logged_in              = "Do not restart"
      start_reboot_timer_immediately = false
      startup_disk                   = "Current Startup Disk"
      user_logged_in                 = "Do not restart"
    }
  }
}

resource "jamfpro_policy" "policy_sequoia_cmmc_lvl1_audit" {
  name            = "US CMMC 2.0 Level 1 - Audit (Sequoia) ${var.entropy_string}"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sequoia_cmmc_lvl1_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_computers.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sequoia_cmmc_lvl1_compliance.id
      parameter4 = "--check"
    }

    maintenance {
      recon = true
    }

    reboot {
      file_vault_2_reboot            = false
      message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
      minutes_until_reboot           = 5
      no_user_logged_in              = "Do not restart"
      start_reboot_timer_immediately = false
      startup_disk                   = "Current Startup Disk"
      user_logged_in                 = "Do not restart"
    }
  }
}

resource "jamfpro_policy" "policy_sequoia_cmmc_lvl1_remediation" {
  name            = "US CMMC 2.0 Level 1 - Remediation (Sequoia) ${var.entropy_string}"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sequoia_cmmc_lvl1_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_cmmc_lvl1_non_compliant.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sequoia_cmmc_lvl1_compliance.id
      parameter4 = "--check"
      parameter5 = "--fix"
      parameter6 = "--check"
    }

    maintenance {
      recon = true
    }

    reboot {
      file_vault_2_reboot            = false
      message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
      minutes_until_reboot           = 5
      no_user_logged_in              = "Do not restart"
      start_reboot_timer_immediately = false
      startup_disk                   = "Current Startup Disk"
      user_logged_in                 = "Do not restart"
    }
  }
}

## Define configuration profile details for Sonoma
locals {
  sonoma_cmmc_lvl1_dict = {
    "Application Access"     = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-applicationaccess.mobileconfig"
    "Assistant"              = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-assistant.support.mobileconfig"
    "iCloud"                 = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-icloud.managed.mobileconfig"
    "Login Window"           = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-loginwindow.mobileconfig"
    "MCX"                    = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-MCX.mobileconfig"
    "Sharing Preferences"    = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-preferences.sharing.SharingPrefsExtension.mobileconfig"
    "Firewall"               = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-security.firewall.mobileconfig"
    "Security"               = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-security.mobileconfig"
    "Setup Assistant"        = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-SetupAssistant.managed.mobileconfig"
    "Software Update"        = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-SoftwareUpdate.mobileconfig"
    "Submit Diagnostic Info" = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-SubmitDiagInfo.mobileconfig"
    "System Policy Control"  = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-systempolicy.control.mobileconfig"
    "System Preferences"     = "${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-systempreferences.mobileconfig"
  }
}

## Create configuration profiles for Sonoma
resource "jamfpro_macos_configuration_profile_plist" "sonoma_cmmc_lvl1" {
  for_each            = local.sonoma_cmmc_lvl1_dict
  name                = "Sonoma US CMMC 2.0 Level 1 - ${each.key} ${var.entropy_string}"
  description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'US CMMC 2.0 Level 1 - Sonoma Computers' Smart Group and remove the placeholder serial number criteria."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sonoma_cmmc_lvl1_benchmarks.id
  level               = "System"

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_computers.id]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "sonoma_cmmc_lvl1_smart_card" {
  name                = "Sonoma US CMMC 2.0 Level 1 - Smart Card ${var.entropy_string}"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sonoma_cmmc_lvl1_benchmarks.id
  level               = "System"

  payloads         = file("${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-security.smartcard.mobileconfig")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = []
  }
}

## Define configuration profile details for Sequoia
locals {
  sequoia_cmmc_lvl1_dict = {
    "Accessibility"          = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-Accessibility.mobileconfig"
    "Application Access"     = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-applicationaccess.mobileconfig"
    "Assistant"              = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-assistant.support.mobileconfig"
    "iCloud"                 = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-icloud.managed.mobileconfig"
    "Login Window"           = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-loginwindow.mobileconfig"
    "MCX"                    = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-MCX.mobileconfig"
    "Photos Shared Defauts"  = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-photos.shareddefaults.mobileconfig"
    "Firewall"               = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-security.firewall.mobileconfig"
    "Setup Assistant"        = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-SetupAssistant.managed.mobileconfig"
    "Software Update"        = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-SoftwareUpdate.mobileconfig"
    "Submit Diagnostic Info" = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-SubmitDiagInfo.mobileconfig"
    "System Policy Control"  = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-systempolicy.control.mobileconfig"
    "System Preferences"     = "${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-systempreferences.mobileconfig"
  }
}

## Create configuration profiles for Sequoia
resource "jamfpro_macos_configuration_profile_plist" "sequoia_cmmc_lvl1" {
  for_each            = local.sequoia_cmmc_lvl1_dict
  name                = "Sequoia US CMMC 2.0 Level 1 - ${each.key} ${var.entropy_string}"
  description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'US CMMC 2.0 Level 1 - Sequoia Computers' Smart Group and remove the placeholder serial number criteria."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sequoia_cmmc_lvl1_benchmarks.id
  level               = "System"

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_computers.id]
  }
  depends_on = [jamfpro_macos_configuration_profile_plist.sonoma_cmmc_lvl1]
}

resource "jamfpro_macos_configuration_profile_plist" "sequoia_cmmc_lvl1_smart_card" {
  name                = "Sequoia US CMMC 2.0 Level 1 - Smart Card ${var.entropy_string}"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sequoia_cmmc_lvl1_benchmarks.id
  level               = "System"

  payloads         = file("${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-security.smartcard.mobileconfig")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = []
  }
}
