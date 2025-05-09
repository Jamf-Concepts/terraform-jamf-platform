## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.19.1"
    }
  }
}

module "configuration-jamf-pro-smart-groups" {
  source                = "../configuration-jamf-pro-smart-groups"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  # providers = {
  #   jamfpro.jpro = jamfpro.jpro
  # }
}

module "configuration-jamf-pro-categories" {
  source                = "../configuration-jamf-pro-categories"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  # providers = {
  #   jamfpro.jpro = jamfpro.jpro
  # }
}

module "configuration-jamf-pro-computer-management-settings" {
  source                = "../configuration-jamf-pro-computer-management-settings"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  # providers = {
  #   jamfpro.jpro = jamfpro.jpro
  # }
}

module "management-macOS-rosetta" {
  source                = "../management-macOS-rosetta"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  # providers = {
  #   jamfpro.jpro = jamfpro.jpro
  # }
}

module "microsoft_365" {
  source                = "../management-macOS-microsoft-365"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  # providers = {
  #   jamfpro.jpro = jamfpro.jpro
  # }
}
