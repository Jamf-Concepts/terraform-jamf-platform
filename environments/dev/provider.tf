# Credentials are supplied via terraform.tfvars — see Prerequisites in README.md

provider "jamfplatform" {
  base_url      = var.jamfplatform_base_url
  client_id     = var.jamfplatform_client_id
  client_secret = var.jamfplatform_client_secret
  tenant_id     = var.jamfplatform_tenant_id
}
