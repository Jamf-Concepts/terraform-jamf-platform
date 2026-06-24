## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = "0.18.0-rc.2"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create Smart Computer Groups - Quality Of Life
resource "jamfplatform_device_group" "group_sonoma_computers" {
  name        = "*Sonoma Macs"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "14."
    },
  ]
}

resource "jamfplatform_device_group" "group_sequoia_computers" {
  name        = "*Sequoia Macs"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Operating System Version"
      operator = "like"
      value    = "15."
    },
  ]
}

resource "jamfplatform_device_group" "group_last_checkin" {
  name        = "*7 Days Since Last Check-In"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Last Check-in"
      operator = "more than x days ago"
      value    = "7"
    },
  ]
}

resource "jamfplatform_device_group" "group_available_swu" {
  name        = "*Available Software Updates"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Number of Available Updates"
      operator = "more than"
      value    = "0"
    },
  ]
}

## Create Smart Mobile Device Groups - Quality Of Life

resource "jamfplatform_device_group" "supervised_ios" {
  name = "*Supervised Devices"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Supervised"
      operator = "is"
      value    = "Supervised"
    },
  ]
}

resource "jamfplatform_device_group" "unsupervised_ios" {
  name = "*Un-Supervised Devices"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Supervised"
      operator = "is"
      value    = "Unsupervised"
    },
  ]
}

resource "jamfplatform_device_group" "byod_ios" {
  name = "*BYOD Devices"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Serial Number"
      operator = "like"
      value    = ""
    },
  ]
}

resource "jamfplatform_device_group" "ios_17" {
  name = "*Devices Running iOS 17"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "OS Version"
      operator = "like"
      value    = "17."
    },
  ]
}

resource "jamfplatform_device_group" "ios_18" {
  name = "*Devices Running iOS 18"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "OS Version"
      operator = "like"
      value    = "18."
    },
  ]
}

resource "jamfplatform_device_group" "group_last_checkin_mobile" {
  name = "*Last Check-In More Than a Week Ago"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Last Inventory Update"
      operator = "more than x days ago"
      value    = "7"
    },
  ]
}

resource "jamfplatform_device_group" "group_used_space_above_75" {
  name = "*Used Storage above 75 percent"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Used Space Percentage"
      operator = "more than"
      value    = "75"
    },
  ]
}

resource "jamfplatform_device_group" "group_passcode_not_present" {
  name = "*Passcode Not Present"

  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Passcode Status"
      operator = "is"
      value    = "Not Present"
    },
  ]
}
