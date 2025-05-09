## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.19.1"
    }
  }
}

module "management-iOS-configuration-profiles" {
  source                = "../management-iOS-configuration-profiles"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  # providers = {
  #   jamfpro.jpro = jamfpro.jpro
  # }
}
