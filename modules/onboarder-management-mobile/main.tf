## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

module "management-iOS-configuration-profiles" {
  source                = "../management-iOS-configuration-profiles"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}
