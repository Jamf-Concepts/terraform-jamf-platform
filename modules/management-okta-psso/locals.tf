locals {
  okta_device_access_scep = templatefile("${path.module}/support_files/Okta Device Access SCEP.tpl", {
    okta_short_url     = var.okta_short_url
    okta_org_name      = var.okta_org_name
    okta_scep_url      = var.okta_scep_url
    okta_psso_client   = var.okta_psso_client
    okta_scep_username = var.okta_scep_username
    okta_scep_password = var.okta_scep_password
  })
}

locals {
  okta_verify_psso_setup = templatefile("${path.module}/support_files/Okta Verify for PSSO at Setup.tpl", {
    okta_short_url     = var.okta_short_url
    okta_org_name      = var.okta_org_name
    okta_scep_url      = var.okta_scep_url
    okta_psso_client   = var.okta_psso_client
    okta_scep_username = var.okta_scep_username
    okta_scep_password = var.okta_scep_password
  })
}

locals {
  okta_verify_psso_app_config = templatefile("${path.module}/support_files/Okta Verify App Configuration.tpl", {
    okta_short_url     = var.okta_short_url
    okta_org_name      = var.okta_org_name
    okta_scep_url      = var.okta_scep_url
    okta_psso_client   = var.okta_psso_client
    okta_scep_username = var.okta_scep_username
    okta_scep_password = var.okta_scep_password
  })
}
