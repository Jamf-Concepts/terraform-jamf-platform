locals {
  # 1) normalize case & trim
  _lower = lower(trimspace(var.okta_short_url))

  # 2) strip protocol using replace() (old-TF-compatible)
  _no_proto = replace(replace(local._lower, "https://", ""), "http://", "")

  # 3) remove any path
  _host_part = split("/", local._no_proto)[0]

  # 4) FIXED: correct argument order (split(separator, string))
  _host_no_port = split(":", local._host_part)[0]

  # 5) final normalized domain
  okta_domain = local._host_no_port
}

locals {
  okta_device_access_scep = templatefile("${path.module}/support_files/Okta Device Access SCEP.tpl", {
    okta_short_url     = local.okta_domain
    okta_org_name      = var.okta_org_name
    okta_scep_url      = var.okta_scep_url
    okta_psso_client   = var.okta_psso_client
    okta_scep_username = var.okta_scep_username
    okta_scep_password = var.okta_scep_password
  })
}

locals {
  okta_verify_psso_setup = templatefile("${path.module}/support_files/Okta Verify for PSSO at Setup.tpl", {
    okta_short_url     = local.okta_domain
    okta_org_name      = var.okta_org_name
    okta_scep_url      = var.okta_scep_url
    okta_psso_client   = var.okta_psso_client
    okta_scep_username = var.okta_scep_username
    okta_scep_password = var.okta_scep_password
  })
}

locals {
  okta_verify_psso_app_config = templatefile("${path.module}/support_files/Okta Verify App Configuration.tpl", {
    okta_short_url     = local.okta_domain
    okta_org_name      = var.okta_org_name
    okta_scep_url      = var.okta_scep_url
    okta_psso_client   = var.okta_psso_client
    okta_scep_username = var.okta_scep_username
    okta_scep_password = var.okta_scep_password
  })
}
