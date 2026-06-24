## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = "0.18.0-rc.2"
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
  api_roles           = [jamfplatform_pro_api_role.workbrew_api_role.display_name]
  credential_rotation = "1"
}
