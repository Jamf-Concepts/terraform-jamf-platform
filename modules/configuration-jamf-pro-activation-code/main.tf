## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

resource "jamfpro_activation_code" "activation_code_001" {
  organization_name = var.organization_name
  code              = var.jamf_pro_activation_code
}
