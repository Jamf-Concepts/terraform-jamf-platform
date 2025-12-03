locals {
  # Define the header mapping for different SaaS applications
  proxy_set_headers = join("\n", flatten([
    for domain in var.allowed_domains : (
      var.saas_application == "Microsoft" ? [
        "proxy_set_header 'Restrict-Access-To-Tenants' ${domain};",
        "proxy_set_header 'Restrict-Access-Context' ${domain};"
      ] : [
        "proxy_set_header '${local.header_mapping[var.saas_application]}' ${domain};"
      ]
    )
  ]))

  header_mapping = {
    Google    = "X-GooGApps-Allowed-Domains"
    Slack     = "X-Slack-Allowed-Workspaces-Requester"
    Dropbox   = "X-Dropbox-allowed-Team-Ids"
  }

  rendered_nginx_config = templatefile("${path.module}/nginx.conf.tpl", {
    proxy_set_headers = local.proxy_set_headers
    proxy_pass        = lookup(
      {
        Google    = "proxy_pass https://accounts.google.com;"
        Microsoft = "proxy_pass https://login.microsoftonline.com;"
        Slack     = "proxy_pass https://slack.com/signin;"
        Dropbox   = "proxy_pass https://www.dropbox.com/login;"
      },
      var.saas_application,
      "proxy_pass https://default.url;"
    )
  })

  hostname_mapping = {
    Google    = "accounts.google.com"
    Microsoft = "login.microsoftonline.com"
    Slack     = "slack.com"
    Dropbox   = "dropbox.com"
  }

  hostname = lookup(local.hostname_mapping, var.saas_application, "default.hostname.com")

  rendered_userdata = templatefile("${path.module}/init.sh.tpl", {
    nginx_config = local.rendered_nginx_config
    server_ext = local.server_ext_content
    cert_pem     = local.use_provided_certificates ? file(var.certificate_file) : tls_locally_signed_cert.leaf[0].cert_pem
    private_key  = local.use_provided_certificates ? file(var.private_key_file) : tls_private_key.leaf[0].private_key_pem
  })
}


