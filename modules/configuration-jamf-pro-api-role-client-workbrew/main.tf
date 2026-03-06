## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

resource "jamfpro_api_role" "workbrew_api_role" {
  display_name = "Workbrew"
  privileges = [
    "Read Smart Computer Groups",
    "Read Computers",
    "Read Static Computer Groups",
    "Read Accounts"
  ]
}

resource "jamfpro_api_integration" "workbrew_api_integeration" {
  display_name         = "Workbrew"
  enabled              = true
  authorization_scopes = [jamfpro_api_role.workbrew_api_role.display_name]
}

# Data source to retrieve the full API integration details including client_secret
data "jamfpro_api_integration" "workbrew_api_integeration_data" {
  id = jamfpro_api_integration.workbrew_api_integeration.id
}