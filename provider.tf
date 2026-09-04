# Supply credentials in terraform.tfvars. See Prerequisites in README.md.

provider "jamfplatform" {
  base_url       = var.jamfplatform_base_url
  client_id      = var.jamfplatform_client_id
  client_secret  = var.jamfplatform_client_secret
  environment_id = var.jamfplatform_environment_id
}
