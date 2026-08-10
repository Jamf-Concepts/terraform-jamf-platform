## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.26.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

module "configuration-jamf-pro-smart-groups" {
  source                = "../configuration-jamf-pro-smart-groups"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-pro-categories" {
  source                = "../configuration-jamf-pro-categories"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-pro-computer-management-settings" {
  source                = "../configuration-jamf-pro-computer-management-settings"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-macOS-rosetta" {
  source                = "../management-macOS-rosetta"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}
