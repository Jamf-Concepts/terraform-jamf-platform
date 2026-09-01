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

## jamfplatform_pro_api_role and jamfplatform_pro_api_client were withdrawn from
## the provider at Platform API GA (credential management for Jamf Pro API
## integrations moved to Jamf Account, human-only, no API path) -- there is
## currently no programmatic way to mint an API integration for Workbrew at
## all. Not a Foundations-onboarder concern (this module is unused there,
## gated behind include_workbrew_api_role_client which Foundations never
## sets), but left as a no-op rather than deleted so the shared repo's
## Terraform graph stays valid for every onboarder on this branch. Outputs
## below return null until Jamf restores a programmatic path or Workbrew
## accepts a different credential type.
