## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

resource "jamfplatform_pro_api_role" "workbrew_api_role" {
  display_name = "Workbrew"
  privileges = [
    "Read Smart Computer Groups",
    "Read Computers",
    "Read Static Computer Groups",
    "Read Accounts"
  ]
}

resource "jamfplatform_pro_api_client" "workbrew_api_integeration" {
  display_name        = "Workbrew"
  enabled             = true
  credential_rotation = "1"
  api_roles           = [jamfplatform_pro_api_role.workbrew_api_role.display_name]
}

# Data source to retrieve the full API integration details including client_secret
data "jamfplatform_pro_api_client" "workbrew_api_integeration_data" {
  id = jamfplatform_pro_api_client.workbrew_api_integeration.id
}