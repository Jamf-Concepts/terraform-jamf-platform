## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

resource "jamfplatform_pro_category" "workbrew_category" {
  name     = "Workbrew"
  priority = 9
}


resource "jamfplatform_pro_script" "workbrew_script" {
  name            = "Workbrew Activation"
  os_requirements = ""
  priority        = "BEFORE"
  info            = "Script to activate Workbrew agent on macOS devices."
  notes           = ""
  script          = file("${path.module}/support_files/Workbrew Activation.sh")
  parameter_4     = "Workbrew Workspace API Key"
  parameter_5     = ""
  parameter_6     = ""
  parameter_7     = ""
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

resource "jamfplatform_pro_package" "workbrew_package" {
  package_file_source = "https://console.workbrew.com/downloads/macos"
  category_id         = jamfplatform_pro_category.workbrew_category.id
  priority            = 1
  reboot_required     = false
  display_name        = local.workbrew_package_name != "" ? local.workbrew_package_name : "Workbrew"
}

resource "jamfplatform_pro_computer_extension_attribute" "workbrew_installed_ea" {
  name              = "Workbrew Installed"
  enabled           = true
  input_type        = "SCRIPT"
  description       = "Checks if the Workbrew agent is installed."
  data_type         = "STRING"
  inventory_display = "EXTENSION_ATTRIBUTES"
  script            = file("${path.module}/support_files/Workbrew Installed.sh")
}

resource "jamfplatform_pro_computer_extension_attribute" "workbrew_version_ea" {
  name              = "Workbrew Version"
  enabled           = true
  input_type        = "SCRIPT"
  description       = "Retrieves the installed version of the Workbrew."
  data_type         = "INTEGER"
  inventory_display = "EXTENSION_ATTRIBUTES"
  script            = file("${path.module}/support_files/Workbrew Version.sh")
}

resource "jamfplatform_pro_computer_extension_attribute" "homebrew_version_ea" {
  name              = "Homebrew Version"
  enabled           = true
  input_type        = "SCRIPT"
  description       = "Retrieves the installed version of Homebrew."
  data_type         = "STRING"
  inventory_display = "EXTENSION_ATTRIBUTES"
  script            = file("${path.module}/support_files/Homebrew Version.sh")
}

resource "jamfplatform_pro_macos_configuration_profile" "workbrew_managed_login_item" {


  general = {
    name                = "Workbrew Managed Login Item"
    description         = ""
    level               = "System"
    distribution_method = "Install Automatically"
    redeploy_on_update  = "Newly Assigned"
    payloads            = file("${path.module}/support_files/Workbrew Managed Login Item.mobileconfig")
    user_removable      = false
    category_id         = jamfplatform_pro_category.workbrew_category.id
  }
  scope = {
    targets = {
      all_computers = true
    }
  }
}

resource "jamfplatform_device_group" "workbrew_target_smart_computer_group" {
  name        = "Workbrew Target Target Group"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than or equal"
      value    = "13.0"
    },
    {
      and_or   = "and"
      criteria = "Serial Number"
      operator = "like"
      value    = "111222333444555"
    },
  ]
}

resource "jamfplatform_device_group" "workbrew_installed_smart_computer_group" {
  name = "Workbrew Installed"

  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = jamfplatform_pro_computer_extension_attribute.workbrew_installed_ea.name
      operator = "is"
      value    = "Installed"
    },
  ]
}

resource "jamfplatform_device_group" "workbrew_not_installed_smart_computer_group" {
  name = "Workbrew Not Installed"

  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = jamfplatform_pro_computer_extension_attribute.workbrew_installed_ea.name
      operator = "is"
      value    = "Not Installed"
    },
    {
      and_or   = "or"
      criteria = jamfplatform_pro_computer_extension_attribute.workbrew_installed_ea.name
      operator = "is"
      value    = ""
    },
  ]
}

resource "jamfplatform_pro_policy" "workbrew_install_policy" {



  general = {
    name                        = "Install Workbrew Agent"
    enabled                     = true
    trigger_enrollment_complete = true
    trigger_checkin             = true
    frequency                   = "Once per computer"
    category_id                 = jamfplatform_pro_category.workbrew_category.id
  }
  scope = {
    targets = {
      all_computers      = false
      computer_group_ids = [jamfplatform_device_group.workbrew_target_smart_computer_group.jamf_pro_id]
    }
  }
  packages = {
    distribution_point = "default"
    packages = [
      {
        id                          = jamfplatform_pro_package.workbrew_package.id
        action                      = "Install"
        fill_user_template          = false
        fill_existing_user_template = false
      },
    ]
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.workbrew_script.id
        priority   = "Before"
        parameter4 = var.workbrew_workspace_api_key
        parameter5 = ""
        parameter6 = ""
      },
    ]
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