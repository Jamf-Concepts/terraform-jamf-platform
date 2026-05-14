terraform {
  required_version = ">= 1.11.0"

  required_providers {
    jamfplatform = {
      source  = "Jamf-Concepts/jamfplatform"
      version = ">= 0.1.0"
    }
  }
}
