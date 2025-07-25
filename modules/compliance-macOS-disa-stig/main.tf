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
resource "jamfpro_category" "category_sonoma_stig_benchmarks" {
  name     = "Sonoma - DISA STIG Benchmarks"
  priority = 9
}

resource "jamfpro_category" "category_sequoia_stig_benchmarks" {
  name     = "Sequoia - DISA STIG Benchmarks"
  priority = 9
}

## Create scripts
resource "jamfpro_script" "script_sonoma_stig_compliance" {
  name            = "Sonoma - DISA STIG Compliance"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/computer_scripts/sonoma_stig_compliance.sh")
  category_id     = jamfpro_category.category_sonoma_stig_benchmarks.id
  info            = "This script will apply a set of rules related to the DISA STIG benchmark for macOS Sonoma"
}

resource "jamfpro_script" "script_sequoia_stig_compliance" {
  name            = "Sequoia - DISA STIG Compliance"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/computer_scripts/sequoia_stig_compliance.sh")
  category_id     = jamfpro_category.category_sequoia_stig_benchmarks.id
  info            = "This script will apply a set of rules related to the DISA STIG benchmark for macOS Sequoia"
}

## Create computer extension attributes
resource "jamfpro_computer_extension_attribute" "ea_stig_failed_count" {
  name                   = "DISA STIG - Failed Results Count"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "INTEGER"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsCount.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_stig_failed_list" {
  name                   = "DISA STIG - Failed Results List"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsList.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_stig_version" {
  name                   = "DISA STIG - Compliance Version"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-version.sh")
}

## Create Smart Computer Groups
resource "jamfpro_smart_computer_group" "group_sonoma_computers" {
  name = "DISA STIG - Sonoma Computers"
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

resource "jamfpro_smart_computer_group" "group_sonoma_stig_non_compliant" {
  name = "DISA STIG - Sonoma - Non Compliant Computers"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "14."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = jamfpro_computer_extension_attribute.ea_stig_failed_count.name
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 1
  }
}

resource "jamfpro_smart_computer_group" "group_sequoia_computers" {
  name = "DISA STIG - Sequoia Computers"
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

resource "jamfpro_smart_computer_group" "group_sequoia_stig_non_compliant" {
  name = "DISA STIG - Sequoia - Non Compliant Computers"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = jamfpro_computer_extension_attribute.ea_stig_failed_count.name
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 1
  }
}

## Create policies
resource "jamfpro_policy" "policy_sonoma_stig_audit" {
  name            = "DISA STIG - Audit (Sonoma)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sonoma_stig_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_computers.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sonoma_stig_compliance.id
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

resource "jamfpro_policy" "policy_sonoma_stig_remediation" {
  name            = "DISA STIG - Remediation (Sonoma)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sonoma_stig_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_stig_non_compliant.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sonoma_stig_compliance.id
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

resource "jamfpro_policy" "policy_sequoia_stig_audit" {
  name            = "DISA STIG - Audit (Sequoia)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sequoia_stig_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_computers.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sequoia_stig_compliance.id
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

resource "jamfpro_policy" "policy_sequoia_stig_remediation" {
  name            = "DISA STIG - Remediation (Sequoia)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sequoia_stig_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_stig_non_compliant.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sequoia_stig_compliance.id
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
  sonoma_stig_dict = {
    "Application Access"            = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-applicationaccess.mobileconfig"
    "Application Access Additional" = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-applicationaccess.new.mobileconfig"
    "Assistant"                     = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-assistant.support.mobileconfig"
    "Dock"                          = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-dock.mobileconfig"
    "Global Preferences"            = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-GlobalPreferences.mobileconfig"
    "iCloud"                        = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-icloud.managed.mobileconfig"
    "Login Window"                  = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-loginwindow.mobileconfig"
    "MCX"                           = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-MCX.mobileconfig"
    "MCX Bluetooth"                 = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-MCXBluetooth.mobileconfig"
    "mDNS Responder"                = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-mDNSResponder.mobileconfig"
    "Password Policy"               = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-mobiledevice.passwordpolicy.mobileconfig"
    "Sharing Preferences"           = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-preferences.sharing.SharingPrefsExtension.mobileconfig"
    "Screen Saver"                  = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-screensaver.mobileconfig"
    "Firewall"                      = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-security.firewall.mobileconfig"
    "Setup Assistant"               = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-SetupAssistant.managed.mobileconfig"
    "Software Update"               = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-SoftwareUpdate.mobileconfig"
    "Submit Diag Info"              = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-SubmitDiagInfo.mobileconfig"
    "System Policy Control"         = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-systempolicy.control.mobileconfig"
    "System Preferences"            = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-systempreferences.mobileconfig"
    "Managed Client"                = "${path.module}/support_files/computer_config_profiles/Sonoma_stig-timed.mobileconfig"
  }
}

## Create configuration profiles for Sonoma
resource "jamfpro_macos_configuration_profile_plist" "sonoma_stig" {
  for_each            = local.sonoma_stig_dict
  name                = "Sonoma DISA STIG - ${each.key}"
  description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'DISA STIG - Sonoma Computers' Smart Group and remove the placeholder serial number criteria."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sonoma_stig_benchmarks.id
  level               = "System"

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_computers.id]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "sonoma_stig_smart_card" {
  name                = "Sonoma DISA STIG - Smart Card"
  description         = "To scope this configuration profile, navigate to the Scope tab above and add the 'DISA STIG - Sonoma Computers' smart group. Then, be sure to navigate to Smart Computer Groups, select that group and remove the placeholder serial number. This configuration profile is not scoped intentionally due to potential issues that Smart Cards may cause on an endpoint."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sonoma_stig_benchmarks.id
  level               = "System"

  payloads         = file("${path.module}/support_files/computer_config_profiles/Sonoma_stig-security.smartcard.mobileconfig")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = []
  }
}

## Define configuration profile details for Sequoia part 1
locals {
  sequoia_stig_dict = {
    "Accessibility"                 = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-Accessibility.mobileconfig"
    "Application Access"            = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-applicationaccess.mobileconfig"
    "Application Access Additional" = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-applicationaccess.new.mobileconfig"
    "Assistant"                     = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-assistant.support.mobileconfig"
    "Dock"                          = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-dock.mobileconfig"
    "Global Preferences"            = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-GlobalPreferences.mobileconfig"
    "iCloud"                        = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-icloud.managed.mobileconfig"
    "Login Window"                  = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-loginwindow.mobileconfig"
    "MCX"                           = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-MCX.mobileconfig"
    "MCX Bluetooth"                 = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-MCXBluetooth.mobileconfig"
    "mDNS Responder"                = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-mDNSResponder.mobileconfig"
    "Password Policy"               = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-mobiledevice.passwordpolicy.mobileconfig"
    "Screen Saver"                  = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-screensaver.mobileconfig"
    "Firewall"                      = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-security.firewall.mobileconfig"
    "Setup Assistant"               = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-SetupAssistant.managed.mobileconfig"
    "Software Update"               = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-SoftwareUpdate.mobileconfig"
    "Submit Diag Info"              = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-SubmitDiagInfo.mobileconfig"
    "System Policy Control"         = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-systempolicy.control.mobileconfig"
    "System Preferences"            = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-systempreferences.mobileconfig"
    "Managed Client"                = "${path.module}/support_files/computer_config_profiles/Sequoia_stig-timed.mobileconfig"
  }
}

## Create configuration profiles for Sequoia part 1
resource "jamfpro_macos_configuration_profile_plist" "sequoia_stig" {
  for_each            = local.sequoia_stig_dict
  name                = "Sequoia DISA STIG - ${each.key}"
  description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'DISA STIG - Sequoia Computers' Smart Group and remove the placeholder serial number criteria."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sequoia_stig_benchmarks.id
  level               = "System"

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_computers.id]
  }
  depends_on = [jamfpro_macos_configuration_profile_plist.sonoma_stig]
}

resource "jamfpro_macos_configuration_profile_plist" "sequoia_stig_smart_card" {
  name                = "Sequoia DISA STIG - Smart Card"
  description         = "To scope this configuration profile, navigate to the Scope tab above and add the 'DISA STIG - Sequoia Computers' smart group. Then, be sure to navigate to Smart Computer Groups, select that group and remove the placeholder serial number. This configuration profile is not scoped intentionally due to potential issues that Smart Cards may cause on an endpoint."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sequoia_stig_benchmarks.id
  level               = "System"

  payloads         = file("${path.module}/support_files/computer_config_profiles/Sequoia_stig-security.smartcard.mobileconfig")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = []
  }
}
