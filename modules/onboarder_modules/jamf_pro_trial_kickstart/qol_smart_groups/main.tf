## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.5"
    }
  }
}

## Create Smart Computer Groups - Quality Of Life
resource "jamfpro_smart_computer_group" "group_sonoma_computers" {
  name = "* Sonoma Macs"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "14."
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_sequoia_computers" {
  name = "* Sequoia Macs"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_last_checkin" {
  name = "* 7 Days Since Last Check-In"
  criteria {
    name        = "Last Check-in"
    search_type = "more than x days ago"
    value       = "7"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_disk_encrypted" {
  name = "* FileVault 2 Enabled"
  criteria {
    name        = "FileVault 2 Partition Encryption State"
    search_type = "is"
    value       = "Encrypted"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_available_swu" {
  name = "* Available Software Updates"
  criteria {
    name        = "Number of Available Updates"
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_mobile_device_group" "supervised_ios" {
  name = "Supervised Devices"

  criteria {
    name        = "Supervised"
    priority    = 0
    search_type = "is"
    value       = "Supervised"
  }
}

resource "jamfpro_smart_mobile_device_group" "unsupervised_ios" {
  name = "Un-Supervised Devices"

  criteria {
    name        = "Supervised"
    priority    = 0
    search_type = "is"
    value       = "Unsupervised"
  }
}

resource "jamfpro_smart_mobile_device_group" "byod_ios" {
  name = "BYOD Devices"

  criteria {
    name        = "Serial Number"
    priority    = 0
    search_type = "like"
    value       = ""
  }
}

resource "jamfpro_smart_mobile_device_group" "ios_17" {
  name = "Devices Running iOS 17"

  criteria {
    name        = "OS Version"
    priority    = 0
    search_type = "like"
    value       = "17."
  }
}

resource "jamfpro_smart_mobile_device_group" "ios_18" {
  name = "Devices Running iOS 18"

  criteria {
    name        = "OS Version"
    priority    = 0
    search_type = "like"
    value       = "18."
  }
}
