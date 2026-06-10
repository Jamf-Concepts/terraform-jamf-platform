## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

## Create Categories
resource "jamfpro_category" "sentinelone" {
  name     = "SentinelOne"
  priority = 9
}

## SentinelOne Configuration Profiles
# Deploys 4 configuration profiles from .mobileconfig files:
#   1. Service Management    — Managed Login Items
#   2. Network Filter        — Content Filter / socket filter validation
#   3. Network Extension     — System Extension for network monitoring
#   4. Privacy Control       — PPPC / Full Disk Access

resource "jamfpro_macos_configuration_profile_plist" "sentinelone_service_management" {
  name                = "SentinelOne - Service Management"
  description         = "Prevents removal of SentinelOne Launch Agents and Launch Daemons via Managed Login Items."
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.sentinelone.id
  payload_validate    = false
  user_removable      = false

  payloads = file("${path.module}/support_files/SentinelOne_Service_Management.mobileconfig")

  scope {
    all_computers = true
    all_jss_users = false
  }
}

resource "jamfpro_macos_configuration_profile_plist" "sentinelone_network_filter" {
  name                = "SentinelOne - Network Filter Validation"
  description         = "Authorizes SentinelOne Network Filter automatic validation."
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.sentinelone.id
  payload_validate    = false
  user_removable      = false

  payloads = file("${path.module}/support_files/SentinelOne_Network_Filter_Validation.mobileconfig")

  scope {
    all_computers = true
    all_jss_users = false
  }
}

resource "jamfpro_macos_configuration_profile_plist" "sentinelone_network_extension" {
  name                = "SentinelOne - Network Monitoring Extension"
  description         = "Enables automatic loading of SentinelOne System Extension."
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.sentinelone.id
  payload_validate    = false
  user_removable      = false

  payloads = file("${path.module}/support_files/SentinelOne_Network_Monitoring_Extension.mobileconfig")

  scope {
    all_computers = true
    all_jss_users = false
  }
}

resource "jamfpro_macos_configuration_profile_plist" "sentinelone_privacy_control" {
  name                = "SentinelOne - Privacy Control"
  description         = "Provides Full Disk Access to SentinelOne agent processes."
  level               = "System"
  distribution_method = "Install Automatically"
  redeploy_on_update  = "Newly Assigned"
  category_id         = jamfpro_category.sentinelone.id
  payload_validate    = false
  user_removable      = false

  payloads = file("${path.module}/support_files/SentinelOne_Privacy_Control.mobileconfig")

  scope {
    all_computers = true
    all_jss_users = false
  }
}

## Smart Computer Groups
resource "jamfpro_smart_computer_group" "sentinelone_target" {
  name = "SentinelOne Target Group"
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

resource "jamfpro_smart_computer_group" "sentinelone_installed" {
  name = "SentinelOne Installed"

  criteria {
    name        = "Application Title"
    priority    = 0
    search_type = "has"
    value       = "SentinelOne Extensions.app"
  }
}

resource "jamfpro_smart_computer_group" "sentinelone_not_installed" {
  name = "SentinelOne NOT Installed"

  criteria {
    name        = "Application Title"
    priority    = 0
    and_or      = "and"
    search_type = "does not have"
    value       = "SentinelOne Extensions.app"
  }

  criteria {
    name        = "Profile Name"
    priority    = 1
    and_or      = "and"
    search_type = "has"
    value       = "SentinelOne - Privacy Control"
  }
}

## SentinelOne Package Upload
resource "jamfpro_package" "sentinelone_installer" {
  package_name          = local.sentinelone_pkg_name
  package_file_source   = local.sentinelone_pkg_source
  category_id           = jamfpro_category.sentinelone.id
  info                  = "SentinelOne macOS Agent installer package"
  notes                 = "Managed by Terraform"
  priority              = 10
  reboot_required       = false
  fill_existing_users   = false
  fill_user_template    = false
  os_install            = false
  suppress_updates      = false
  suppress_from_dock    = false
  suppress_eula         = false
  suppress_registration = false

  timeouts {
    create = "90m"
  }

  depends_on = [local_file.sentinelone_pkg, terraform_data.download_sentinelone_pkg]
}

## SentinelOne Install Script
resource "jamfpro_script" "sentinelone_install" {
  name            = "SentinelOne License and Install"
  script_contents = file("${path.module}/support_files/scripts/sentinelone_install.sh")
  category_id     = jamfpro_category.sentinelone.id
  os_requirements = ""
  priority        = "AFTER"
  info            = "This script will install and license SentinelOne silently."
  notes           = "Token is passed via policy parameter 4."
  parameter4      = "SentinelOne Organization Token"
  parameter5      = "SentinelOne Package Filename"
}

## SentinelOne Deployment Policy
resource "jamfpro_policy" "sentinelone_deploy" {
  name            = "Deploy SentinelOne Agent"
  enabled         = true
  trigger_checkin = true
  frequency       = "Once per computer"
  category_id     = jamfpro_category.sentinelone.id

  payloads {
    packages {
      distribution_point = "default"
      package {
        id                          = jamfpro_package.sentinelone_installer.id
        action                      = "Cache"
        fill_user_template          = false
        fill_existing_user_template = false
      }
    }

    scripts {
      id         = jamfpro_script.sentinelone_install.id
      priority   = "After"
      parameter4 = var.sentinelone_org_token
      parameter5 = local.sentinelone_pkg_name
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

    computer_group_ids = [jamfpro_smart_computer_group.sentinelone_target.id]
  }
}
