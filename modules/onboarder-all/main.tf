## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.11"
    }
    jsc = {
      source  = "danjamf/jsctfprovider"
      version = ">= 0.0.15"
    }
  }
}

module "onboarder-management-macOS" {
  source                = "../onboarder-management-macOS"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}

module "onboarder-management-mobile" {
  source                = "../onboarder-management-mobile"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}

module "compliance-macOS-cis-level-1" {
  source                = "../compliance-macOS-cis-level-1"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}

module "compliance-iOS-cis-level-1" {
  source                = "../compliance-iOS-cis-level-1"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}

module "management-macOS-SSOe-Okta" {
  source                = "../management-macOS-SSOe-Okta"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}

module "configuration-jamf-security-cloud-all-services" {
  source                = "../configuration-jamf-security-cloud-all-services"
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
}

module "configuration-jamf-security-cloud-block-pages" {
  source          = "../configuration-jamf-security-cloud-block-pages"
  block_page_logo = var.block_page_logo
  jsc_username    = var.jsc_username
  jsc_password    = var.jsc_password
}

module "endpoint-security-macOS-filevault" {
  source                = "../endpoint-security-macOS-filevault"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}

module "onboarder-app-installers" {
  source                = "../onboarder-app-installers"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
}
