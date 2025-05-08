locals {
  use_provided_certificates = var.certificate_file != "" && var.private_key_file != ""
}
locals {
  leaf_certificate_cn = lookup(
    {
      Google     = "*.google.com",
      Microsoft  = "stamp2.login.microsoftonline.com",
      Slack      = "slack.com",
      Dropbox    = "*.dropbox.com"
    },
    var.saas_application,
    ""
  )
}

locals {
  saas_dns_names = lookup(
    {
      Google     = ["*.google.com", "accounts.google.com"],
      Microsoft  = [
      "stamp2.login.microsoftonline.com",
        "login.microsoftonline-int.com",
        "login.microsoftonline-p.com",
        "login.microsoftonline.com",
        "login2.microsoftonline-int.com",
        "login2.microsoftonline.com",
        "loginex.microsoftonline-int.com",
        "loginex.microsoftonline.com",
        "stamp2.login.microsoftonline-int.com"
      ],
      Slack      = ["slack.com", "*.slack.com"],
      Dropbox    = ["*.dropbox.com", "dropbox.com"]
    },
    var.saas_application,
    []
  )
}
resource "tls_private_key" "root" {
  count    = local.use_provided_certificates ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "root" {
  count              = local.use_provided_certificates ? 0 : 1
  private_key_pem    = tls_private_key.root[0].private_key_pem
  validity_period_hours = 8760
  allowed_uses       = ["cert_signing", "crl_signing"]
  is_ca_certificate = true
  set_authority_key_id = true
  set_subject_key_id = true


  subject {
    common_name = "jscproxy-root"
    organizational_unit = "Security"
    organization = "Jamf"
    locality = "Minneapolis"
    province = "Minnesota"
    country = "US"
  }
}

resource "tls_private_key" "leaf" {
  count    = local.use_provided_certificates ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "leaf" {
  count           = local.use_provided_certificates ? 0 : 1
  private_key_pem = tls_private_key.leaf[0].private_key_pem

  subject {
    common_name = local.leaf_certificate_cn
    organizational_unit = "Security"
    organization = "Jamf"
    locality = "Minneapolis"
    province = "Minnesota"
    country = "US"
  }
    dns_names = local.saas_dns_names
}

resource "tls_locally_signed_cert" "leaf" {
  count                = local.use_provided_certificates ? 0 : 1
  cert_request_pem     = tls_cert_request.leaf[0].cert_request_pem
  ca_private_key_pem   = tls_private_key.root[0].private_key_pem
  ca_cert_pem          = tls_self_signed_cert.root[0].cert_pem
  validity_period_hours = 8760
  allowed_uses         = ["server_auth", "digital_signature", "key_encipherment"]
  set_subject_key_id   = true
}
