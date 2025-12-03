## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
    jsc = {
      source                = "Jamf-Concepts/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}

module "onboarder-management-macOS" {
  source                = "../onboarder-management-macOS"
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "onboarder-management-mobile" {
  source                = "../onboarder-management-mobile"
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-macOS-cis-level-1" {
  source                = "../compliance-macOS-cis-level-1"
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-iOS-cis-level-1" {
  source                = "../compliance-iOS-cis-level-1"
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "management-macOS-SSOe-Okta" {
  source                = "../management-macOS-SSOe-Okta"
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "configuration-jamf-security-cloud-all-services" {
  source                = "../configuration-jamf-security-cloud-all-services"
  okta_client_id        = var.okta_client_id
  okta_org_domain       = var.okta_org_domain
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

module "endpoint-security-macOS-filevault" {
  source                = "../endpoint-security-macOS-filevault"
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

variable "app_installers" {
  type = list(string)
  default = [
    "Adobe Creative Cloud",
    "Box Drive",
    "Dropbox",
    "Google Chrome",
    "Google Drive",
    "JamfCheck",
    "Microsoft Edge",
    "Microsoft Teams",
    "Microsoft Word 365",
    "Microsoft Excel 365",
    "Microsoft PowerPoint 365",
    "Microsoft Outlook 365",
    "Microsoft OneDrive",
    "Mozilla Firefox",
    "Nudge",
    "Slack",
    "TextExpander",
    "Zoom Client for Meetings"
  ]
}

module "management-app-installers" {
  source                = "../management-app-installers"
  for_each              = toset(var.app_installers)
  app_installer_name    = each.value
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "configuration-jamf-security-cloud-jamf-pro" {
  source                = "../configuration-jamf-security-cloud-jamf-pro"
  jamfpro_instance_fqdn = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

module "configuration-jamf-pro-jamf-protect" {
  source                      = "../configuration-jamf-pro-jamf-protect"
  jamfpro_instance_fqdn       = var.jamfpro_instance_fqdn
  jamfpro_client_id           = var.jamfpro_client_id
  jamfpro_client_secret       = var.jamfpro_client_secret
  jamfprotect_url             = var.jamfprotect_url
  jamfprotect_client_id       = var.jamfprotect_client_id
  jamfprotect_client_password = var.jamfprotect_client_password
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}
