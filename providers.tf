## Root provider requirements
terraform {
  required_version = ">= 1.5" # this repo runs on OpenTofu; action/action_trigger blocks are not supported
  required_providers {
    jamfplatform = {
      source  = "jamf/jamfplatform"
      version = ">= 0.32.0"
    }
    jsc = {
      source  = "Jamf-Concepts/jsctfprovider"
      version = ">= 0.0.23"
    }
  }
}

## Jamf Platform provider root configuration
provider "jamfplatform" {
  base_url       = var.jamfplatform_base_url
  client_id      = var.jamfplatform_client_id
  client_secret  = var.jamfplatform_client_secret
  environment_id = var.jamfplatform_environment_id
}

provider "jamfplatform" {
  alias          = "jpro"
  base_url       = var.jamfplatform_base_url
  client_id      = var.jamfplatform_client_id
  client_secret  = var.jamfplatform_client_secret
  environment_id = var.jamfplatform_environment_id
}

# JSC provider root configuration
provider "jsc" {
  username          = var.jsc_username
  password          = var.jsc_password
  applicationid     = var.jsc_application_id
  applicationsecret = var.jsc_application_secret
}

provider "jsc" {
  alias             = "jsc"
  username          = var.jsc_username
  password          = var.jsc_password
  applicationid     = var.jsc_application_id
  applicationsecret = var.jsc_application_secret
}
