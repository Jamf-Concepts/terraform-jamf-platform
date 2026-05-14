terraform {
  required_version = ">= 1.14.0"

  required_providers {
    jamfplatform = {
      source  = "Jamf-Concepts/jamfplatform"
      version = ">= 0.1.0"
    }
  }
}
