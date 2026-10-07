terraform {
  required_version = ">= 1.14.0"

  required_providers {
    jamfplatform = {
      source  = "jamf/jamfplatform"
      version = ">= 1.0.0"
    }
  }
}
