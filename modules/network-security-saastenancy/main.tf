
terraform {
  required_providers {
    jsc = {
      source                = "Jamf-Concepts/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
    jamfplatform = {
      source                = "jamf/jamfplatform"
      version               = ">= 0.32.0"
      configuration_aliases = [jamfplatform.jpro]
    }
    aws = {
    }
  }
}




