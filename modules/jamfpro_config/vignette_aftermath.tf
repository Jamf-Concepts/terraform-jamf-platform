## Create extension attributes
resource "jamfpro_computer_extension_attribute" "ea_aftermath_analyze_trigger" {
    name = "Aftermath Analyze Trigger"
    input_type = "Script"
    enabled = true
    data_type = "string"
    inventory_display = "Extension Attributes"
    input_script = file("support_files/computer_extension_attributes/aftermath_analyze_trigger.sh")
}

resource "jamfpro_computer_extension_attribute" "ea_aftermath_trigger" {
    name = "Aftermath Trigger"
    input_type = "Script"
    enabled = true
    data_type = "string"
    inventory_display = "Extension Attributes"
    input_script = file("support_files/computer_extension_attributes/aftermath_trigger.sh")
}

## Create smart groups
resource "jamfpro_smart_computer_group" "group_aftermath_analyze_trigger" {
  name = "Aftermath Analyze Trigger"
  criteria {
    name          = "Aftermath Analyze Trigger"
    search_type   = "is"
    value         = "analyze"
  }
}

resource "jamfpro_smart_computer_group" "group_aftermath_collection_trigger" {
  name = "Aftermath Collection Trigger"
  criteria {
    name          = "Aftermath Trigger"
    search_type   = "is"
    value         = "aftermath"
  }
}

## Upload packages
resource "jamfpro_package" "package_aftermath" {
    package_name = "Aftermath.pkg"
    info = "Version 2.2.1 - March 8 2024"
    category_id = jamfpro_category.category_security_compliance.id
    package_file_source = "https://github.com/jamf/aftermath/releases/download/v2.2.1/Aftermath.pkg"
    os_install = false
    fill_user_template = false
    priority = 10
    reboot_required = false
    suppress_eula = false
    suppress_from_dock = false
    suppress_registration = false
    suppress_updates = false
}

## Import scripts
resource "jamfpro_script" "script_aftermath_analyze" {
    name = "Vignette.Behavioral.IR-Aftermath-Analyze.sh"
    priority = "AFTER"
    script_contents = file("support_files/computer_scripts/aftermath_analyze.sh")
    category_id = jamfpro_category.category_security_compliance.id
    info = "This script will run Aftermath on a system, analyze the output, and open the storyline.csv file after analysis is complete. Messages are presented throughout the process to communicate what is happening."
}

resource "jamfpro_script" "script_aftermath_collection" {
    name = "Vignette.Behavioral.IR-Aftermath-Collection.sh"
    priority = "AFTER"
    script_contents = file("support_files/computer_scripts/aftermath_collection.sh")
    category_id = jamfpro_category.category_security_compliance.id
}

## Create policies
resource "jamfpro_policy" "policy_install_aftermath" {
  name                          = "Install Aftermath.pkg"
  enabled                       = true
  trigger_enrollment_complete   = true
  trigger_other                 = "EVENT" // "USER_INITIATED" for self service trigger , "EVENT" for an event trigger
  frequency                     = "Once per computer"
  retry_event                   = "check-in"
  retry_attempts                = 3
  notify_on_each_failed_retry   = false
  target_drive                  = "/"
  category_id                   = jamfpro_category.category_security_compliance.id

  scope {
    all_computers = true
  }

  payloads {
    packages {
      distribution_point = "default" // Set the appropriate distribution point
      package {
        id                          = jamfpro_package.package_aftermath.id
        action                      = "Install" // The action to perform with the package (e.g., Install, Cache, etc.)
        fill_user_template          = false     // Whether to fill the user template
        fill_existing_user_template = false     // Whether to fill existing user templates
      }
    }
    maintenance {
      recon = true
    }
  }
}

resource "jamfpro_policy" "policy_aftermath_analysis" {
  name                          = "Vignette.Behavioral.IR-Aftermath-Analysis"
  enabled                       = true
  trigger_other                 = "@aftermathAnalysis" // "USER_INITIATED" for self service trigger , "EVENT" for an event trigger
  frequency                     = "Ongoing"
  target_drive                  = "/"
  category_id                   = jamfpro_category.category_security_compliance.id

  scope {
    all_computers = false
    computer_group_ids = [jamfpro_smart_computer_group.group_aftermath_analyze_trigger.id]
  }

  self_service {
    use_for_self_service            = true
    self_service_display_name       = "Aftermath Analysis"
    install_button_text             = "Analyze"
    self_service_description        = file("support_files/computer_policies/aftermath_analyze_self_service_desc.txt")
    force_users_to_view_description = false
    feature_on_main_page = false
  }

  payloads {
    scripts {
        id = jamfpro_script.script_aftermath_analyze.id
    }
  }
}

resource "jamfpro_policy" "policy_aftermath_collection" {
  name                          = "Vignette.Behavioral.IR-Aftermath-Collection"
  enabled                       = true
  trigger_other                 = "@aftermathCollection" // "USER_INITIATED" for self service trigger , "EVENT" for an event trigger
  frequency                     = "Ongoing"
  target_drive                  = "/"
  category_id                   = jamfpro_category.category_security_compliance.id

  scope {
    all_computers = false
    computer_group_ids = [jamfpro_smart_computer_group.group_aftermath_collection_trigger.id]
  }

  self_service {
    use_for_self_service            = true
    self_service_display_name       = "Aftermath Incident Response Log Collection"
    install_button_text             = "Collect"
    self_service_description        = file("support_files/computer_policies/aftermath_collection_self_service_desc.txt")
    force_users_to_view_description = false
    feature_on_main_page = false
  }

  payloads {
    scripts {
        id = jamfpro_script.script_aftermath_collection.id
    }
  }
}