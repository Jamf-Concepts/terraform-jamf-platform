## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.11"
    }
  }
}

resource "random_id" "entropy" {
  keepers = {
    first = "${timestamp()}"
  }
  byte_length = 1
}

## Create categories
resource "jamfpro_category" "category_sonoma_800_171_benchmarks" {
  name     = "Sonoma - NIST 800-171 Benchmarks [${random_id.entropy.hex}]"
  priority = 9
}

resource "jamfpro_category" "category_sequoia_800_171_benchmarks" {
  name     = "Sequoia - NIST 800-171 Benchmarks [${random_id.entropy.hex}]"
  priority = 9
}

## Create scripts
resource "jamfpro_script" "script_sonoma_800_171_compliance" {
  name            = "Sonoma - NIST 800-171 Compliance [${random_id.entropy.hex}]"
  priority        = "AFTER"
  script_contents = file("${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_scripts/sonoma_800-171_compliance.sh")
  category_id     = jamfpro_category.category_sonoma_800_171_benchmarks.id
  info            = "This script will apply a set of rules related to the NIST 800-171 benchmark for macOS Sonoma"
}

resource "jamfpro_script" "script_sequoia_800_171_compliance" {
  name            = "Sequoia - NIST 800-171 Compliance [${random_id.entropy.hex}]"
  priority        = "AFTER"
  script_contents = file("${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_scripts/sequoia_800-171_compliance.sh")
  category_id     = jamfpro_category.category_sequoia_800_171_benchmarks.id
  info            = "This script will apply a set of rules related to the NIST 800-171 benchmark for macOS Sequoia"
}

## Create computer extension attributes
resource "jamfpro_computer_extension_attribute" "ea_800_171_failed_count" {
  name                   = "NIST 800-171 - Failed Results Count [${random_id.entropy.hex}]"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "INTEGER"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_extension_attributes/compliance-FailedResultsCount.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_800_171_failed_list" {
  name                   = "NIST 800-171 - Failed Results List [${random_id.entropy.hex}]"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_extension_attributes/compliance-FailedResultsList.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_800_171_version" {
  name                   = "Compliance Version [${random_id.entropy.hex}]"
  input_type             = "SCRIPT"
  enabled                = true
  data_type              = "STRING"
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  script_contents        = file("${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_extension_attributes/compliance-version.sh")
}

## Create Smart Computer Groups
resource "jamfpro_smart_computer_group" "group_sonoma_computers" {
  name = "NIST 800-171 - Sonoma Computers [${random_id.entropy.hex}]"
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
  name = "NIST 800-171 - Sonoma - Non Compliant Computers [${random_id.entropy.hex}]"
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
  name = "NIST 800-171 - Sequoia Computers [${random_id.entropy.hex}]"
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
  name = "NIST 800-171 - Sequoia - Non Compliant Computers [${random_id.entropy.hex}]"
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
  name            = "NIST 800-171 - Audit (Sonoma) [${random_id.entropy.hex}]"
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
  name            = "NIST 800-171 - Remediation (Sonoma) [${random_id.entropy.hex}]"
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
  name            = "NIST 800-171 - Audit (Sequoia) [${random_id.entropy.hex}]"
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
  name            = "NIST 800-171 - Remediation (Sequoia) [${random_id.entropy.hex}]"
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
    "Application Access"    = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-applicationaccess.mobileconfig"
    "Assistant Support"     = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-assistant.support.mobileconfig"
    "Disc Recording"        = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-DiscRecording.mobileconfig"
    "Dock"                  = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-dock.mobileconfig"
    "Apple IR Controller"   = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-driver.AppleIRController.mobileconfig"
    "Finder"                = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-finder.mobileconfig"
    "Global Preferences"    = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-GlobalPreferences.mobileconfig"
    "iCloud"                = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-icloud.managed.mobileconfig"
    "Login Window"          = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-loginwindow.mobileconfig"
    "MCX"                   = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-MCX.mobileconfig"
    "MCX Bluetooth"         = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-MCXBluetooth.mobileconfig"
    "mDNS Responder"        = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-mDNSResponder.mobileconfig"
    "Password Policy"       = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-mobiledevice.passwordpolicy.mobileconfig"
    "Sharing Preferences"   = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-preferences.sharing.SharingPrefsExtension.mobileconfig"
    "Screen Saver"          = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-screensaver.mobileconfig"
    "Firewall"              = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-security.firewall.mobileconfig"
    "Security"              = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-security.mobileconfig"
    "Smart Card"            = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-security.smartcard.mobileconfig"
    "Setup Assistant"       = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-SetupAssistant.managed.mobileconfig"
    "Submit Diag Info"      = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-SubmitDiagInfo.mobileconfig"
    "System Policy Control" = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-systempolicy.control.mobileconfig"
    "Managed System Policy" = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-systempolicy.managed.mobileconfig"
    "System Preferences"    = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-systempreferences.mobileconfig"
    "Managed Client"        = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sonoma_800-171-timed.mobileconfig"
  }
}

## Create configuration profiles for Sonoma
resource "jamfpro_macos_configuration_profile_plist" "sonoma_800_171" {
  for_each            = local.sonoma_800_171_dict
  name                = "Sonoma NIST 800-171 - ${each.key} [${random_id.entropy.hex}]"
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

## Define configuration profile details for Sequoia part 1
locals {
  sequoia_800_171_dict = {
    "Accessibility"         = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-Accessibility.mobileconfig"
    "Application Access"    = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-applicationaccess.mobileconfig"
    "Assistant Support"     = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-assistant.support.mobileconfig"
    "Disc Recording"        = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-DiscRecording.mobileconfig"
    "Dock"                  = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-dock.mobileconfig"
    "Apple IR Controller"   = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-driver.AppleIRController.mobileconfig"
    "Finder"                = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-finder.mobileconfig"
    "Global Preferences"    = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-GlobalPreferences.mobileconfig"
    "iCloud"                = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-icloud.managed.mobileconfig"
    "Login Window"          = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-loginwindow.mobileconfig"
    "MCX"                   = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-MCX.mobileconfig"
    "MCX Bluetooth"         = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-MCXBluetooth.mobileconfig"
    "mDNS Responder"        = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-mDNSResponder.mobileconfig"
    "Password Policy"       = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-mobiledevice.passwordpolicy.mobileconfig"
    "Screen Saver"          = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-screensaver.mobileconfig"
    "Firewall"              = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-security.firewall.mobileconfig"
    "Smart Card"            = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-security.smartcard.mobileconfig"
    "Setup Assistant"       = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-SetupAssistant.managed.mobileconfig"
    "Submit Diag Info"      = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-SubmitDiagInfo.mobileconfig"
    "System Policy Control" = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-systempolicy.control.mobileconfig"
    "Managed System Policy" = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-systempolicy.managed.mobileconfig"
    "System Preferences"    = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-systempreferences.mobileconfig"
    "Managed Client"        = "${var.support_files_path_prefix}modules/trusted_access_outcomes/endpoint_compliance/computers/mac_800_171_benchmark/support_files/computer_config_profiles/Sequoia_800-171-timed.mobileconfig"
  }
}

## Create configuration profiles for Sequoia part 1
resource "jamfpro_macos_configuration_profile_plist" "sequoia_800_171" {
  for_each            = local.sequoia_800_171_dict
  name                = "Sequoia NIST 800-171 - ${each.key} [${random_id.entropy.hex}]"
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
