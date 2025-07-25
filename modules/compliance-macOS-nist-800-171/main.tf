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
resource "jamfpro_category" "category_sonoma_800_171_benchmarks" {
  name     = "Sonoma - NIST 800-171 Benchmarks"
  priority = 9
}

resource "jamfpro_category" "category_sequoia_800_171_benchmarks" {
  name     = "Sequoia - NIST 800-171 Benchmarks"
  priority = 9
}

## Create scripts
resource "jamfpro_script" "script_sonoma_800_171_compliance" {
  name            = "Sonoma - NIST 800-171 Compliance"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/computer_scripts/sonoma_800-171_compliance.sh")
  category_id     = jamfpro_category.category_sonoma_800_171_benchmarks.id
  info            = "This script will apply a set of rules related to the NIST 800-171 benchmark for macOS Sonoma"
}

resource "jamfpro_script" "script_sequoia_800_171_compliance" {
  name            = "Sequoia - NIST 800-171 Compliance"
  priority        = "AFTER"
  script_contents = file("${path.module}/support_files/computer_scripts/sequoia_800-171_compliance.sh")
  category_id     = jamfpro_category.category_sequoia_800_171_benchmarks.id
  info            = "This script will apply a set of rules related to the NIST 800-171 benchmark for macOS Sequoia"
}

## Create computer extension attributes
resource "jamfpro_computer_extension_attribute" "ea_800_171_failed_count" {
  name                   = "NIST 800-171 - Failed Results Count"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "INTEGER"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsCount.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_800_171_failed_list" {
  name                   = "NIST 800-171 - Failed Results List"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-FailedResultsList.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_800_171_version" {
  name                   = "NIST 800-171 - Compliance Version"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${path.module}/support_files/computer_extension_attributes/compliance-version.sh")
}

## Create Smart Computer Groups
resource "jamfpro_smart_computer_group" "group_sonoma_computers" {
  name = "NIST 800-171 - Sonoma Computers"
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

resource "jamfpro_smart_computer_group" "group_sonoma_800_171_non_compliant" {
  name = "NIST 800-171 - Sonoma - Non Compliant Computers"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "14."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = jamfpro_computer_extension_attribute.ea_800_171_failed_count.name
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 1
  }
}

resource "jamfpro_smart_computer_group" "group_sequoia_computers" {
  name = "NIST 800-171 - Sequoia Computers"
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

resource "jamfpro_smart_computer_group" "group_sequoia_800_171_non_compliant" {
  name = "NIST 800-171 - Sequoia - Non Compliant Computers"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
  criteria {
    name        = jamfpro_computer_extension_attribute.ea_800_171_failed_count.name
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 1
  }
}

## Create policies
resource "jamfpro_policy" "policy_sonoma_800_171_audit" {
  name            = "NIST 800-171 - Audit (Sonoma)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sonoma_800_171_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_computers.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sonoma_800_171_compliance.id
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

resource "jamfpro_policy" "policy_sonoma_800_171_remediation" {
  name            = "NIST 800-171 - Remediation (Sonoma)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sonoma_800_171_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_800_171_non_compliant.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sonoma_800_171_compliance.id
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

resource "jamfpro_policy" "policy_sequoia_800_171_audit" {
  name            = "NIST 800-171 - Audit (Sequoia)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sequoia_800_171_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_computers.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sequoia_800_171_compliance.id
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

resource "jamfpro_policy" "policy_sequoia_800_171_remediation" {
  name            = "NIST 800-171 - Remediation (Sequoia)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.category_sequoia_800_171_benchmarks.id

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_800_171_non_compliant.id]
  }

  self_service {
    use_for_self_service = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.script_sequoia_800_171_compliance.id
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
  sonoma_800_171_dict = {
    "Application Access"    = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-applicationaccess.mobileconfig"
    "Assistant Support"     = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-assistant.support.mobileconfig"
    "Disc Recording"        = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-DiscRecording.mobileconfig"
    "Dock"                  = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-dock.mobileconfig"
    "Apple IR Controller"   = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-driver.AppleIRController.mobileconfig"
    "Finder"                = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-finder.mobileconfig"
    "Global Preferences"    = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-GlobalPreferences.mobileconfig"
    "iCloud"                = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-icloud.managed.mobileconfig"
    "Login Window"          = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-loginwindow.mobileconfig"
    "MCX"                   = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-MCX.mobileconfig"
    "MCX Bluetooth"         = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-MCXBluetooth.mobileconfig"
    "mDNS Responder"        = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-mDNSResponder.mobileconfig"
    "Password Policy"       = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-mobiledevice.passwordpolicy.mobileconfig"
    "Sharing Preferences"   = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-preferences.sharing.SharingPrefsExtension.mobileconfig"
    "Screen Saver"          = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-screensaver.mobileconfig"
    "Firewall"              = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-security.firewall.mobileconfig"
    "Security"              = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-security.mobileconfig"
    "Setup Assistant"       = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-SetupAssistant.managed.mobileconfig"
    "Submit Diag Info"      = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-SubmitDiagInfo.mobileconfig"
    "System Policy Control" = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-systempolicy.control.mobileconfig"
    "Managed System Policy" = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-systempolicy.managed.mobileconfig"
    "System Preferences"    = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-systempreferences.mobileconfig"
    "Managed Client"        = "${path.module}/support_files/computer_config_profiles/Sonoma_800-171-timed.mobileconfig"
  }
}

## Create configuration profiles for Sonoma
resource "jamfpro_macos_configuration_profile_plist" "sonoma_800_171" {
  for_each            = local.sonoma_800_171_dict
  name                = "Sonoma NIST 800-171 - ${each.key}"
  description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'NIST 800-171 - Sonoma Computers' Smart Group and remove the placeholder serial number criteria."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sonoma_800_171_benchmarks.id
  level               = "System"

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sonoma_computers.id]
  }
}

resource "jamfpro_macos_configuration_profile_plist" "sonoma_800_171_smart_card" {
  name                = "Sonoma NIST 800-171 - Smart Card"
  description         = "To scope this configuration profile, navigate to the Scope tab above and add the 'NIST 800-171 - Sonoma Computers' smart group. Then, be sure to navigate to Smart Computer Groups, select that group and remove the placeholder serial number. This configuration profile is not scoped intentionally due to potential issues that Smart Cards may cause on an endpoint."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sonoma_800_171_benchmarks.id
  level               = "System"

  payloads         = file("${path.module}/support_files/computer_config_profiles/Sonoma_800-171-security.smartcard.mobileconfig")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = []
  }
}

## Define configuration profile details for Sequoia part 1
locals {
  sequoia_800_171_dict = {
    "Accessibility"         = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-Accessibility.mobileconfig"
    "Application Access"    = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-applicationaccess.mobileconfig"
    "Assistant Support"     = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-assistant.support.mobileconfig"
    "Disc Recording"        = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-DiscRecording.mobileconfig"
    "Dock"                  = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-dock.mobileconfig"
    "Apple IR Controller"   = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-driver.AppleIRController.mobileconfig"
    "Finder"                = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-finder.mobileconfig"
    "Global Preferences"    = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-GlobalPreferences.mobileconfig"
    "iCloud"                = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-icloud.managed.mobileconfig"
    "Login Window"          = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-loginwindow.mobileconfig"
    "MCX"                   = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-MCX.mobileconfig"
    "MCX Bluetooth"         = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-MCXBluetooth.mobileconfig"
    "mDNS Responder"        = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-mDNSResponder.mobileconfig"
    "Password Policy"       = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-mobiledevice.passwordpolicy.mobileconfig"
    "Photos Shared Defauts" = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-photos.shareddefaults.mobileconfig"
    "Screen Saver"          = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-screensaver.mobileconfig"
    "Firewall"              = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-security.firewall.mobileconfig"
    "Setup Assistant"       = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-SetupAssistant.managed.mobileconfig"
    "Submit Diag Info"      = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-SubmitDiagInfo.mobileconfig"
    "System Policy Control" = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-systempolicy.control.mobileconfig"
    "Managed System Policy" = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-systempolicy.managed.mobileconfig"
    "System Preferences"    = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-systempreferences.mobileconfig"
    "Managed Client"        = "${path.module}/support_files/computer_config_profiles/Sequoia_800-171-timed.mobileconfig"
  }
}

## Create configuration profiles for Sequoia part 1
resource "jamfpro_macos_configuration_profile_plist" "sequoia_800_171" {
  for_each            = local.sequoia_800_171_dict
  name                = "Sequoia NIST 800-171 - ${each.key}"
  description         = "To scope this configuration profile, navigate to Smart Computer Groups, select the 'NIST 800-171 - Sequoia Computers' Smart Group and remove the placeholder serial number criteria."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sequoia_800_171_benchmarks.id
  level               = "System"

  payloads         = file("${each.value}")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = [jamfpro_smart_computer_group.group_sequoia_computers.id]
  }
  depends_on = [jamfpro_macos_configuration_profile_plist.sonoma_800_171]
}

resource "jamfpro_macos_configuration_profile_plist" "sequoia_800_171_smart_card" {
  name                = "Sequoia NIST 800-171 - Smart Card"
  description         = "To scope this configuration profile, navigate to the Scope tab above and add the 'NIST 800-171 - Sequoia Computers' smart group. Then, be sure to navigate to Smart Computer Groups, select that group and remove the placeholder serial number. This configuration profile is not scoped intentionally due to potential issues that Smart Cards may cause on an endpoint."
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.category_sequoia_800_171_benchmarks.id
  level               = "System"

  payloads         = file("${path.module}/support_files/computer_config_profiles/Sequoia_800-171-security.smartcard.mobileconfig")
  payload_validate = false

  scope {
    all_computers      = false
    computer_group_ids = []
  }
}
