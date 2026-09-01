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

## jamfplatform_pro_app_installer was dropped from the provider in v0.29.0-rc.4
## (PR #335 -- reverse-engineered surface with no published spec). App
## Installers are now provisioned directly against the Jamf Pro API by
## modular_onboarder's utils/jamf_app_installers.py after this Terraform apply
## completes, not by this module. Left as a no-op rather than removing the
## module/its callers, since re-adding is possible if Jamf ever publishes a
## real spec for this surface.
