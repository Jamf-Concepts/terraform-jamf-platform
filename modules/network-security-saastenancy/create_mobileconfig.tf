resource "local_file" "mobileconfig" {
  filename = "${path.module}/JSCP_Proxy_Cert.mobileconfig"
  content  = templatefile("${path.module}/mobileconfig.tpl", {
    root_cert_body        = base64encode(tls_self_signed_cert.root[0].cert_pem)
    leaf_cert_body        = base64encode(tls_locally_signed_cert.leaf[0].cert_pem)
  })
}
