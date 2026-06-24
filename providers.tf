## Root provider requirements
terraform {
  required_version = ">= 1.11"
  required_providers {
    jamfplatform = {
      source  = "Jamf-Concepts/jamfplatform"
      version = "0.18.0-rc.2"
    }
    jsc = {
      source  = "Jamf-Concepts/jsctfprovider"
      version = ">= 0.0.23"
    }
  }
}

## Jamf Platform provider root configuration
provider "jamfplatform" {
  alias         = "jpro"
  base_url      = var.jamfplatform_base_url
  client_id     = var.jamfplatform_client_id
  client_secret = var.jamfplatform_client_secret
  tenant_id     = var.jamfplatform_tenant_id
}

# JSC provider root configuration
provider "jsc" {
  alias             = "jsc"
  username          = var.jsc_username
  password          = var.jsc_password
  applicationid     = var.jsc_application_id
  applicationsecret = var.jsc_application_secret
}
