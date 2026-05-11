terraform {
  required_version = ">= 1.11.0"

  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.37.0"
    }
  }
}
