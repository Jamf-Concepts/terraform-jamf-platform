# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Smart_Groups.html
#
# Smart groups used for scoping profiles, policies, and app installers
# throughout this module. Jamf Pro populates membership dynamically
# as devices check in and match criteria — Terraform only manages the group
# definition, not membership.
#
# nudge_is_installed pins a specific Nudge version in both criteria values.
# When upgrading Nudge, update those values here AND the package URL in
# packages.tf to keep the install policy and this exclusion group in sync.

locals {
  architecture_types = {
    apple_silicon = {
      name = "Architecture - Apple Silicon (Managed by Terraform)"
      arch = "arm64"
    },
    intel = {
      name = "Architecture - Intel (Managed by Terraform)"
      arch = "x86_64"
    }
  }
  computer_models = {
    "laptops" = {
      name        = "Model - Laptops (Managed by Terraform)"
      search_type = "like"
      model       = "book"
    }
    "desktops" = {
      name        = "Model - Desktops (Managed by Terraform)"
      search_type = "not like"
      model       = "book"
    }
  }
  os_version_ranges = {
    os_14 = {
      name  = "Operating System - macOS 14 (Managed by Terraform)"
      os_lt = "15.0"
      os_gt = "14.0"
    },
    os_15 = {
      name  = "Operating System - macOS 15 (Managed by Terraform)"
      os_lt = "16.0"
      os_gt = "15.0"
    },
    os_26 = {
      name  = "Operating System - macOS 26 (Managed by Terraform)"
      os_lt = "27.0"
      os_gt = "26.0"
    }
  }
}

resource "jamfplatform_device_group" "computers_architecture" {
  for_each    = local.architecture_types
  name        = each.value.name
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Architecture Type"
      operator = "is"
      value    = each.value.arch
    }
  ]
}

resource "jamfplatform_device_group" "computers_model" {
  for_each    = local.computer_models
  name        = each.value.name
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Model"
      operator = each.value.search_type
      value    = each.value.model
    }
  ]
}

resource "jamfplatform_device_group" "computers_os_version" {
  for_each    = local.os_version_ranges
  name        = each.value.name
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "greater than"
      value    = each.value.os_gt
    },
    {
      criteria = "Operating System Version"
      operator = "less than"
      value    = each.value.os_lt
    }
  ]
}

resource "jamfplatform_device_group" "computers_all_managed" {
  name        = "All Managed (Managed by Terraform)"
  group_type  = "smart"
  device_type = "computer"
  criteria    = []
}

resource "jamfplatform_device_group" "computers_nudge_is_installed" {
  name        = "Nudge Is Installed (Managed by Terraform)"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Application Bundle ID"
      operator = "is"
      value    = "com.github.macadmins.Nudge"
    },
    {
      criteria = "Application Version"
      operator = "is"
      value    = "2.1.3.81860"
    }
  ]
}
