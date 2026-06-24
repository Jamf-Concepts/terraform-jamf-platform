## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = "0.18.0-rc.2"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create categories
resource "jamfplatform_pro_category" "category_sonoma_cmmc_lvl1_benchmarks" {
  name     = "Sonoma - US CMMC 2.0 Level 1 Benchmarks"
  priority = 9
}

resource "jamfplatform_pro_category" "category_sequoia_cmmc_lvl1_benchmarks" {
  name     = "Sequoia - US CMMC 2.0 Level 1 Benchmarks"
  priority = 9
}

resource "jamfplatform_pro_category" "category_tahoe_cmmc_lvl1_benchmarks" {
  name     = "Tahoe - US CMMC 2.0 Level 1 Benchmarks"
  priority = 9
}

## Create scripts
resource "jamfplatform_pro_script" "script_sonoma_cmmc_lvl1_compliance" {
  name     = "Sonoma - US CMMC 2.0 Level 1 Compliance"
  priority = "AFTER"
  info     = "This script will apply a set of rules related to the US CMMC 2.0 Level 1 benchmark for macOS Sonoma"
  script_contents   = file("${path.module}/support_files/computer_scripts/sonoma_cmmc_lvl1_compliance.sh")
}

resource "jamfplatform_pro_script" "script_sequoia_cmmc_lvl1_compliance" {
  name     = "Sequoia - US CMMC 2.0 Level 1 Compliance"
  priority = "AFTER"
  info     = "This script will apply a set of rules related to the US CMMC 2.0 Level 1 benchmark for macOS Sequoia"
  script_contents   = file("${path.module}/support_files/computer_scripts/sequoia_cmmc_lvl1_compliance.sh")
}

resource "jamfplatform_pro_script" "script_tahoe_cmmc_lvl1_compliance" {
  name     = "Tahoe - US CMMC 2.0 Level 1 Compliance"
  priority = "AFTER"
  info     = "This script will apply a set of rules related to the US CMMC 2.0 Level 1 benchmark for macOS Tahoe"
  script_contents   = file("${path.module}/support_files/computer_scripts/tahoe_cmmc_lvl1_compliance.sh")
}

## Create computer extension attributes
resource "jamfplatform_pro_computer_extension_attribute" "ea_cmmc_lvl1_failed_count" {
  name              = "US CMMC 2.0 Level 1 - Failed Results Count"
  input_type        = "SCRIPT"
  enabled           = true
  data_type         = "INTEGER"
  inventory_display = "EXTENSION_ATTRIBUTES"
  script            = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsCount.sh")
}

resource "jamfplatform_pro_computer_extension_attribute" "ea_cmmc_lvl1_failed_list" {
  name              = "US CMMC 2.0 Level 1 - Failed Results List"
  input_type        = "SCRIPT"
  enabled           = true
  data_type         = "STRING"
  inventory_display = "EXTENSION_ATTRIBUTES"
  script            = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsList.sh")
}

resource "jamfplatform_pro_computer_extension_attribute" "ea_cmmc_lvl1_version" {
  name              = "US CMMC 2.0 Level 1 - Compliance Version"
  input_type        = "SCRIPT"
  enabled           = true
  data_type         = "STRING"
  inventory_display = "EXTENSION_ATTRIBUTES"
  script            = file("${path.module}/support_files/computer_extension_attributes/compliance-version.sh")
}

## Create Smart Computer Groups
resource "jamfplatform_device_group" "group_sonoma_computers" {
  name        = "US CMMC 2.0 Level 1 - Sonoma Computers"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "14."
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

resource "jamfplatform_device_group" "group_sonoma_cmmc_lvl1_non_compliant" {
  name        = "US CMMC 2.0 Level 1 - Sonoma - Non Compliant Computers"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "14."
    },
    {
      and_or   = "and"
      criteria = jamfplatform_pro_computer_extension_attribute.ea_cmmc_lvl1_failed_count.name
      operator = "more than"
      value    = "0"
    },
  ]
}

resource "jamfplatform_device_group" "group_sequoia_computers" {
  name        = "US CMMC 2.0 Level 1 - Sequoia Computers"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "15."
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

resource "jamfplatform_device_group" "group_sequoia_cmmc_lvl1_non_compliant" {
  name        = "US CMMC 2.0 Level 1 - Sequoia - Non Compliant Computers"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "15."
    },
    {
      and_or   = "and"
      criteria = jamfplatform_pro_computer_extension_attribute.ea_cmmc_lvl1_failed_count.name
      operator = "more than"
      value    = "0"
    },
  ]
}

resource "jamfplatform_device_group" "group_tahoe_computers" {
  name        = "US CMMC 2.0 Level 1 - Tahoe Computers"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "26."
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

resource "jamfplatform_device_group" "group_tahoe_cmmc_lvl1_non_compliant" {
  name        = "US CMMC 2.0 Level 1 - Tahoe - Non Compliant Computers"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "26."
    },
    {
      and_or   = "and"
      criteria = jamfplatform_pro_computer_extension_attribute.ea_cmmc_lvl1_failed_count.name
      operator = "more than"
      value    = "0"
    },
  ]
}

## Create policies
resource "jamfplatform_pro_policy" "policy_sonoma_cmmc_lvl1_audit" {



  general = {
    name            = "US CMMC 2.0 Level 1 - Audit (Sonoma)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.category_sonoma_cmmc_lvl1_benchmarks.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_sonoma_computers.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service = false
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.script_sonoma_cmmc_lvl1_compliance.id
        parameter4 = "--check"
      },
    ]
  }
  maintenance = {
    recon = true
  }
  restart_options = {
    file_vault_2_reboot            = false
    message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
    minutes_until_reboot           = 5
    no_user_logged_in              = "Do not restart"
    start_reboot_timer_immediately = false
    startup_disk                   = "Current Startup Disk"
    user_logged_in                 = "Do not restart"
  }
}

resource "jamfplatform_pro_policy" "policy_sonoma_cmmc_lvl1_remediation" {



  general = {
    name            = "US CMMC 2.0 Level 1 - Remediation (Sonoma)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.category_sonoma_cmmc_lvl1_benchmarks.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_sonoma_cmmc_lvl1_non_compliant.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service = false
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.script_sonoma_cmmc_lvl1_compliance.id
        parameter4 = "--check"
        parameter5 = "--fix"
        parameter6 = "--check"
      },
    ]
  }
  maintenance = {
    recon = true
  }
  restart_options = {
    file_vault_2_reboot            = false
    message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
    minutes_until_reboot           = 5
    no_user_logged_in              = "Do not restart"
    start_reboot_timer_immediately = false
    startup_disk                   = "Current Startup Disk"
    user_logged_in                 = "Do not restart"
  }
}

resource "jamfplatform_pro_policy" "policy_sequoia_cmmc_lvl1_audit" {



  general = {
    name            = "US CMMC 2.0 Level 1 - Audit (Sequoia)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.category_sequoia_cmmc_lvl1_benchmarks.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_sequoia_computers.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service = false
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.script_sequoia_cmmc_lvl1_compliance.id
        parameter4 = "--check"
      },
    ]
  }
  maintenance = {
    recon = true
  }
  restart_options = {
    file_vault_2_reboot            = false
    message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
    minutes_until_reboot           = 5
    no_user_logged_in              = "Do not restart"
    start_reboot_timer_immediately = false
    startup_disk                   = "Current Startup Disk"
    user_logged_in                 = "Do not restart"
  }
}

resource "jamfplatform_pro_policy" "policy_sequoia_cmmc_lvl1_remediation" {



  general = {
    name            = "US CMMC 2.0 Level 1 - Remediation (Sequoia)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.category_sequoia_cmmc_lvl1_benchmarks.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_sequoia_cmmc_lvl1_non_compliant.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service = false
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.script_sequoia_cmmc_lvl1_compliance.id
        parameter4 = "--check"
        parameter5 = "--fix"
        parameter6 = "--check"
      },
    ]
  }
  maintenance = {
    recon = true
  }
  restart_options = {
    file_vault_2_reboot            = false
    message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
    minutes_until_reboot           = 5
    no_user_logged_in              = "Do not restart"
    start_reboot_timer_immediately = false
    startup_disk                   = "Current Startup Disk"
    user_logged_in                 = "Do not restart"
  }
}

resource "jamfplatform_pro_policy" "policy_tahoe_cmmc_lvl1_audit" {



  general = {
    name            = "US CMMC 2.0 Level 1 - Audit (Tahoe)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.category_tahoe_cmmc_lvl1_benchmarks.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_tahoe_computers.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service = false
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.script_tahoe_cmmc_lvl1_compliance.id
        parameter4 = "--check"
      },
    ]
  }
  maintenance = {
    recon = true
  }
  restart_options = {
    file_vault_2_reboot            = false
    message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
    minutes_until_reboot           = 5
    no_user_logged_in              = "Do not restart"
    start_reboot_timer_immediately = false
    startup_disk                   = "Current Startup Disk"
    user_logged_in                 = "Do not restart"
  }
}

resource "jamfplatform_pro_policy" "policy_tahoe_cmmc_lvl1_remediation" {



  general = {
    name            = "US CMMC 2.0 Level 1 - Remediation (Tahoe)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.category_tahoe_cmmc_lvl1_benchmarks.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_tahoe_cmmc_lvl1_non_compliant.jamf_pro_id]
    }
  }
  self_service = {
    use_for_self_service = false
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.script_tahoe_cmmc_lvl1_compliance.id
        parameter4 = "--check"
        parameter5 = "--fix"
        parameter6 = "--check"
      },
    ]
  }
  maintenance = {
    recon = true
  }
  restart_options = {
    file_vault_2_reboot            = false
    message                        = "This computer will restart in 5 minutes. Please save anything you are working on and log out by choosing Log Out from the bottom of the Apple menu."
    minutes_until_reboot           = 5
    no_user_logged_in              = "Do not restart"
    start_reboot_timer_immediately = false
    startup_disk                   = "Current Startup Disk"
    user_logged_in                 = "Do not restart"
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
resource "jamfplatform_pro_macos_configuration_profile" "sonoma_cmmc_lvl1" {
  for_each = local.sonoma_cmmc_lvl1_dict


  general = {
    name                = "Sonoma US CMMC 2.0 Level 1 - ${each.key}"
    description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'US CMMC 2.0 Level 1 - Sonoma Computers' Smart Group and remove the placeholder serial number criteria."
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    category_id         = jamfplatform_pro_category.category_sonoma_cmmc_lvl1_benchmarks.id
    level               = "Computer Level"
    payloads            = file("${each.value}")
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_sonoma_computers.jamf_pro_id]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "sonoma_cmmc_lvl1_smart_card" {


  general = {
    name                = "Sonoma US CMMC 2.0 Level 1 - Smart Card"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    category_id         = jamfplatform_pro_category.category_sonoma_cmmc_lvl1_benchmarks.id
    level               = "Computer Level"
    payloads            = file("${path.module}/support_files/computer_config_profiles/Sonoma_cmmc_lvl1-security.smartcard.mobileconfig")
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = []
    }
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
resource "jamfplatform_pro_macos_configuration_profile" "sequoia_cmmc_lvl1" {
  for_each = local.sequoia_cmmc_lvl1_dict


  depends_on = [jamfplatform_pro_macos_configuration_profile.sonoma_cmmc_lvl1]
  general = {
    name                = "Sequoia US CMMC 2.0 Level 1 - ${each.key}"
    description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'US CMMC 2.0 Level 1 - Sequoia Computers' Smart Group and remove the placeholder serial number criteria."
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    category_id         = jamfplatform_pro_category.category_sequoia_cmmc_lvl1_benchmarks.id
    level               = "Computer Level"
    payloads            = file("${each.value}")
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_sequoia_computers.jamf_pro_id]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "sequoia_cmmc_lvl1_smart_card" {


  general = {
    name                = "Sequoia US CMMC 2.0 Level 1 - Smart Card"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    category_id         = jamfplatform_pro_category.category_sequoia_cmmc_lvl1_benchmarks.id
    level               = "Computer Level"
    payloads            = file("${path.module}/support_files/computer_config_profiles/Sequoia_cmmc_lvl1-security.smartcard.mobileconfig")
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = []
    }
  }
}

## Define configuration profile details for Tahoe
locals {
  tahoe_cmmc_lvl1_dict = {
    "Accessibility"          = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-Accessibility.mobileconfig"
    "Application Access"     = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-applicationaccess.mobileconfig"
    "Assistant"              = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-assistant.support.mobileconfig"
    "iCloud"                 = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-icloud.managed.mobileconfig"
    "Login Window"           = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-loginwindow.mobileconfig"
    "MCX"                    = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-MCX.mobileconfig"
    "Photos Shared Defauts"  = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-photos.shareddefaults.mobileconfig"
    "Firewall"               = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-security.firewall.mobileconfig"
    "Setup Assistant"        = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-SetupAssistant.managed.mobileconfig"
    "Software Update"        = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-SoftwareUpdate.mobileconfig"
    "Submit Diagnostic Info" = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-SubmitDiagInfo.mobileconfig"
    "System Policy Control"  = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-systempolicy.control.mobileconfig"
    "System Preferences"     = "${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-systempreferences.mobileconfig"
  }
}

## Create configuration profiles for Tahoe
resource "jamfplatform_pro_macos_configuration_profile" "tahoe_cmmc_lvl1" {
  for_each = local.tahoe_cmmc_lvl1_dict


  depends_on = [jamfplatform_pro_macos_configuration_profile.sequoia_cmmc_lvl1]
  general = {
    name                = "Tahoe US CMMC 2.0 Level 1 - ${each.key}"
    description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'US CMMC 2.0 Level 1 - Tahoe Computers' Smart Group and remove the placeholder serial number criteria."
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    category_id         = jamfplatform_pro_category.category_tahoe_cmmc_lvl1_benchmarks.id
    level               = "Computer Level"
    payloads            = file("${each.value}")
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.group_tahoe_computers.jamf_pro_id]
    }
  }
}

resource "jamfplatform_pro_macos_configuration_profile" "tahoe_cmmc_lvl1_smart_card" {


  general = {
    name                = "Tahoe US CMMC 2.0 Level 1 - Smart Card"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    category_id         = jamfplatform_pro_category.category_tahoe_cmmc_lvl1_benchmarks.id
    level               = "Computer Level"
    payloads            = file("${path.module}/support_files/computer_config_profiles/Tahoe_cmmc_lvl1-security.smartcard.mobileconfig")
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = []
    }
  }
}
