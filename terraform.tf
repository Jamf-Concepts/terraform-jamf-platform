terraform {
  required_version = ">= 1.13.0"

  required_providers {
    jamfplatform = {
      source  = "Jamf-Concepts/jamfplatform"
      version = "~> 0.26"
    }
  }
}
