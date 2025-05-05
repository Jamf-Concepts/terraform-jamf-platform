locals {
  server_ext_content = lookup(
    {
      Google = <<EOT
basicConstraints = CA:FALSE
nsCertType = server
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:accounts.google.com, DNS:*.google.com
EOT
      Microsoft = <<EOT
basicConstraints = CA:FALSE
nsCertType = server
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:stamp2.login.microsoftonline.com, DNS:login.microsoftonline-int.com, DNS:login.microsoftonline-p.com, DNS:login.microsoftonline.com, DNS:login2.microsoftonline-int.com, DNS:login2.microsoftonline.com, DNS:loginex.microsoftonline-int.com, DNS:loginex.microsoftonline.com, DNS:stamp2.login.microsoftonline-int.com
EOT
      Slack = <<EOT
basicConstraints = CA:FALSE
nsCertType = server
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:slack.com, DNS:*.slack.com
EOT
      Dropbox = <<EOT
basicConstraints = CA:FALSE
nsCertType = server
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:dropbox.com, DNS:*.dropbox.com
EOT
    },
    var.saas_application,
    ""
  )
}