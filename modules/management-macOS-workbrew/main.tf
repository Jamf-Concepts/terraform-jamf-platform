## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

resource "jamfpro_category" "workbrew_category" {
  name     = "Workbrew"
  priority = 9
}


resource "jamfpro_script" "workbrew_script" {
  name            = "Workbrew Activation"
  script_contents = file("${path.module}/support_files/Workbrew Activation.sh")
  category_id     = jamfpro_category.workbrew_category.id
  os_requirements = ""
  priority        = "BEFORE"
  info            = "Script to activate Workbrew agent on macOS devices."
  notes           = ""
  parameter4      = "Workbrew Workspace API Key"
  parameter5      = ""
  parameter6      = ""
  parameter7      = ""
}

# Download the package to get the filename
resource "null_resource" "download_workbrew" {
  provisioner "local-exec" {
    command = <<-EOT
      curl -sI "https://console.workbrew.com/downloads/macos" | \
      grep -i "content-disposition\|location" | \
      grep -o "Workbrew-[0-9.]*\.pkg" | \
      head -1 > ${path.module}/.workbrew_version.txt
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

data "local_file" "workbrew_version" {
  depends_on = [null_resource.download_workbrew]
  filename   = "${path.module}/.workbrew_version.txt"
}

locals {
  workbrew_package_name = trimspace(data.local_file.workbrew_version.content)
}

resource "jamfpro_package" "workbrew_package" {
  package_name          = local.workbrew_package_name != "" ? local.workbrew_package_name : "Workbrew"
  package_file_source   = "https://console.workbrew.com/downloads/macos"
  category_id           = jamfpro_category.workbrew_category.id
  fill_user_template    = false
  os_install            = false
  priority              = 1
  reboot_required       = false
  suppress_eula         = false
  suppress_from_dock    = false
  suppress_registration = false
  suppress_updates      = false
}

resource "jamfpro_computer_extension_attribute" "workbrew_installed_ea" {
  name                   = "Workbrew Installed"
  enabled                = true
  input_type             = "SCRIPT"
  description            = "Checks if the Workbrew agent is installed."
  script_contents        = file("${path.module}/support_files/Workbrew Installed.sh")
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  data_type              = "STRING"
}

resource "jamfpro_computer_extension_attribute" "workbrew_version_ea" {
  name                   = "Workbrew Version"
  enabled                = true
  input_type             = "SCRIPT"
  description            = "Retrieves the installed version of the Workbrew."
  script_contents        = file("${path.module}/support_files/Workbrew Version.sh")
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  data_type              = "INTEGER"
}

resource "jamfpro_computer_extension_attribute" "homebrew_version_ea" {
  name                   = "Homebrew Version"
  enabled                = true
  input_type             = "SCRIPT"
  description            = "Retrieves the installed version of Homebrew."
  script_contents        = file("${path.module}/support_files/Homebrew Version.sh")
  inventory_display_type = "EXTENSION_ATTRIBUTES"
  data_type              = "STRING"
}

resource "jamfpro_macos_configuration_profile_plist" "workbrew_managed_login_item" {
  name                = "Workbrew Managed Login Item"
  description         = ""
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  payloads            = file("${path.module}/support_files/Workbrew Managed Login Item.mobileconfig")
  payload_validate    = true
  user_removable      = false
  category_id         = jamfpro_category.workbrew_category.id

  scope {
    all_computers = true
    all_jss_users = false
  }

}

resource "jamfpro_smart_computer_group" "workbrew_target_smart_computer_group" {
  name = "Workbrew Target Target Group"
  criteria {
    name        = "Operating System Version"
    search_type = "greater than or equal"
    value       = "13.0"
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

resource "jamfpro_smart_computer_group" "workbrew_installed_smart_computer_group" {
  name = "Workbrew Installed"
  criteria {
    name        = jamfpro_computer_extension_attribute.workbrew_installed_ea.name
    search_type = "is"
    value       = "Installed"
    and_or      = "and"
    priority    = 0
  }

}

resource "jamfpro_smart_computer_group" "workbrew_not_installed_smart_computer_group" {
  name = "Workbrew Not Installed"
  criteria {
    name        = jamfpro_computer_extension_attribute.workbrew_installed_ea.name
    search_type = "is"
    value       = "Not Installed"
    and_or      = "or"
    priority    = 0
  }
  criteria {
    name        = jamfpro_computer_extension_attribute.workbrew_installed_ea.name
    search_type = "is"
    value       = ""
    and_or      = "or"
    priority    = 1
  }

}

resource "jamfpro_policy" "workbrew_install_policy" {
  name                        = "Install Workbrew Agent"
  enabled                     = true
  trigger_enrollment_complete = true
  trigger_checkin             = true
  frequency                   = "Once per computer"
  category_id                 = jamfpro_category.workbrew_category.id

  payloads {
    packages {
      distribution_point = "default"
      package {
        id                          = jamfpro_package.workbrew_package.id
        action                      = "Install"
        fill_user_template          = false
        fill_existing_user_template = false
      }
    }
    scripts {
      id         = jamfpro_script.workbrew_script.id
      priority   = "Before"
      parameter4 = var.workbrew_workspace_api_key
      parameter5 = ""
      parameter6 = ""
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


  scope {
    all_computers = false
    all_jss_users = false

    computer_group_ids = [jamfpro_smart_computer_group.workbrew_target_smart_computer_group.id]
  }
}