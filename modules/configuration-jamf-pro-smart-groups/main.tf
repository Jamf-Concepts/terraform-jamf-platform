## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.5"
    }
  }
}

resource "random_integer" "entropy" {
  min = 10
  max = 999
}

## Create Smart Computer Groups - Quality Of Life
resource "jamfpro_smart_computer_group" "group_sonoma_computers" {
  name = "*Sonoma Macs [${random_integer.entropy.result}]"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "14."
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_sequoia_computers" {
  name = "*Sequoia Macs [${random_integer.entropy.result}]"
  criteria {
    name        = "Operating System Version"
    search_type = "like"
    value       = "15."
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_last_checkin" {
  name = "*7 Days Since Last Check-In [${random_integer.entropy.result}]"
  criteria {
    name        = "Last Check-in"
    search_type = "more than x days ago"
    value       = "7"
    and_or      = "and"
    priority    = 0
  }
}

resource "jamfpro_smart_computer_group" "group_available_swu" {
  name = "*Available Software Updates [${random_integer.entropy.result}]"
  criteria {
    name        = "Number of Available Updates"
    search_type = "more than"
    value       = "0"
    and_or      = "and"
    priority    = 0
  }
}

## Create Smart Mobile Device Groups - Quality Of Life

resource "jamfpro_smart_mobile_device_group" "supervised_ios" {
  name = "*Supervised Devices [${random_integer.entropy.result}]"

  criteria {
    name        = "Supervised"
    priority    = 0
    search_type = "is"
    value       = "Supervised"
  }
}

resource "jamfpro_smart_mobile_device_group" "unsupervised_ios" {
  name = "*Un-Supervised Devices [${random_integer.entropy.result}]"

  criteria {
    name        = "Supervised"
    priority    = 0
    search_type = "is"
    value       = "Unsupervised"
  }
}

resource "jamfpro_smart_mobile_device_group" "byod_ios" {
  name = "*BYOD Devices [${random_integer.entropy.result}]"

  criteria {
    name        = "Serial Number"
    priority    = 0
    search_type = "like"
    value       = ""
  }
}

resource "jamfpro_smart_mobile_device_group" "ios_17" {
  name = "*Devices Running iOS 17 [${random_integer.entropy.result}]"

  criteria {
    name        = "OS Version"
    priority    = 0
    search_type = "like"
    value       = "17."
  }
}

resource "jamfpro_smart_mobile_device_group" "ios_18" {
  name = "*Devices Running iOS 18 [${random_integer.entropy.result}]"

  criteria {
    name        = "OS Version"
    priority    = 0
    search_type = "like"
    value       = "18."
  }
}

resource "jamfpro_smart_mobile_device_group" "group_last_checkin" {
  name = "*Last Check-In More Than a Week Ago [${random_integer.entropy.result}]"

  criteria {
    name        = "Last Inventory Update"
    priority    = 0
    search_type = "more than x days ago"
    value       = "7"
  }
}

resource "jamfpro_smart_mobile_device_group" "group_used_space_above_75" {
  name = "*Used Storage above 75 percent [${random_integer.entropy.result}]"

  criteria {
    name        = "Used Space Percentage"
    priority    = 0
    search_type = "more than"
    value       = "75"
  }
}

resource "jamfpro_smart_mobile_device_group" "group_passcode_not_present" {
  name = "*Passcode Not Present [${random_integer.entropy.result}]"

  criteria {
    name        = "Passcode Status"
    priority    = 0
    search_type = "is"
    value       = "Not Present"
  }
}
