## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.29.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## jamfplatform_pro_api_role and jamfplatform_pro_api_client were withdrawn from
## the provider at Platform API GA (credential management for Jamf Pro API
## integrations moved to Jamf Account, human-only, no API path) -- the three
## roles and one client that used to live here, feeding jsc_uemc below, can no
## longer be created by any credential. jsc_uemc itself (Jamf-Concepts/jsctfprovider)
## is also gone from this module now, replaced by jamfplatform_security_cloud_uem_connect
## below, which sidesteps the whole problem: with platform_tenant auth, Jamf
## Security Cloud provisions and manages its own Jamf Pro credentials directly,
## so nothing here ever needs to mint one.

## The Jamf Pro tenant identifier for the scope this provider is configured
## with -- naming the tenant to Jamf Security Cloud so it can provision its own
## credentials there, instead of us supplying an API integration's client_id/secret.
data "jamfplatform_pro_tenant_id" "jamf_pro" {}

## Jamf Security Cloud allows only one UEM Connect integration per tenant
## (see the provider's CONNECTOR_CONFIG_ALREADY_EXISTS diagnostic). Onboarder
## test tenants commonly already have one from a prior run, and that's an
## expected, non-fatal state -- the rest of the deploy should still apply. The
## caller checks for an existing integration via the Platform API before this
## module runs and passes its id through; when non-empty, this resource is
## skipped entirely and the existing integration's id is reused below instead.
resource "jamfplatform_security_cloud_uem_connect" "jamf_pro" {
  count      = var.uem_connect_already_exists_id == "" ? 1 : 0
  uem_vendor = "JAMF_PRO"

  platform_tenant = {
    tenant_id = data.jamfplatform_pro_tenant_id.jamf_pro.tenant_id
  }
}
