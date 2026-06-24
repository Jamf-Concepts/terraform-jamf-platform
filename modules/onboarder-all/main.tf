## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = "0.18.0-rc.2"
      configuration_aliases = [jamfplatform.jpro]
    }
    jsc = {
      source                = "Jamf-Concepts/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}

module "onboarder-management-macOS" {
  source                = "../onboarder-management-macOS"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "onboarder-management-mobile" {
  source                = "../onboarder-management-mobile"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-macOS-cis-level-1" {
  source                = "../compliance-macOS-cis-level-1"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-iOS-cis-level-1" {
  source                = "../compliance-iOS-cis-level-1"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-macOS-SSOe-Okta" {
  source                = "../management-macOS-SSOe-Okta"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-security-cloud-all-services" {
  source                = "../configuration-jamf-security-cloud-all-services"
  okta_client_id        = var.okta_client_id
  okta_org_domain       = var.okta_org_domain
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc      = jsc.jsc
  }
}

module "endpoint-security-macOS-filevault" {
  source                = "../endpoint-security-macOS-filevault"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
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
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-security-cloud-jamf-pro" {
  source                = "../configuration-jamf-security-cloud-jamf-pro"
  jamfplatform_base_url  = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc      = jsc.jsc
  }
}

module "configuration-jamf-pro-jamf-protect" {
  source                      = "../configuration-jamf-pro-jamf-protect"
  jamfplatform_base_url        = var.jamfplatform_base_url
  jamfplatform_client_id           = var.jamfplatform_client_id
  jamfplatform_client_secret       = var.jamfplatform_client_secret
  jamfprotect_url             = var.jamfprotect_url
  jamfprotect_client_id       = var.jamfprotect_client_id
  jamfprotect_client_password = var.jamfprotect_client_password
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}
