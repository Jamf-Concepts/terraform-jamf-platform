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

  subject {
    common_name = "RootCA"
  }
}

resource "tls_private_key" "intermediate" {
  count    = local.use_provided_certificates ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "intermediate" {
  count           = local.use_provided_certificates ? 0 : 1
  private_key_pem = tls_private_key.intermediate[0].private_key_pem

  subject {
    common_name = "IntermediateCA"
  }
}

resource "tls_locally_signed_cert" "intermediate" {
  count                = local.use_provided_certificates ? 0 : 1
  cert_request_pem     = tls_cert_request.intermediate[0].cert_request_pem
  ca_private_key_pem   = tls_private_key.root[0].private_key_pem
  ca_cert_pem          = tls_self_signed_cert.root[0].cert_pem
  validity_period_hours = 4380
  allowed_uses         = ["cert_signing", "crl_signing"]
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
  }
}

resource "tls_locally_signed_cert" "leaf" {
  count                = local.use_provided_certificates ? 0 : 1
  cert_request_pem     = tls_cert_request.leaf[0].cert_request_pem
  ca_private_key_pem   = tls_private_key.intermediate[0].private_key_pem
  ca_cert_pem          = tls_locally_signed_cert.intermediate[0].cert_pem
  validity_period_hours = 365
  allowed_uses         = ["server_auth", "digital_signature", "key_encipherment"]
}

output "ssl_certificate" {
  value = local.use_provided_certificates ? file(var.certificate_file) : tls_locally_signed_cert.leaf[0].cert_pem
}

output "ssl_private_key" {
  value = local.use_provided_certificates ? file(var.private_key_file) : tls_private_key.leaf[0].private_key_pem
  sensitive = true
}