## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
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
