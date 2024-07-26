## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = "~> 0.1.5"
    }
    jsc = {
      source = "danjamf/jsctfprovider"
      version = "0.0.7"
    }
  }
}

resource "jsc_ap" "ztna" {
    name = "Connect ZTNA"
    oktaconnectionid = var.jsc_provided_idp_client_child
    privateaccess = true
    threatdefence = false
    datapolicy = false
}