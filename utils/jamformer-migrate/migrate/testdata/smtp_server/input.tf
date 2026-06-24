resource "jamfpro_smtp_server" "basic_auth" {
  enabled             = true
  authentication_type = "BASIC"

  connection_settings {
    host               = "smtp.sendgrid.net"
    port               = 587
    encryption_type    = "TLS_1_2"
    connection_timeout = 5
  }

  sender_settings {
    display_name  = "Jamf Pro Server"
    email_address = "user@company.com"
  }

  basic_auth_credentials {
    username = "sample-username"
    password = "password"
  }
}

resource "jamfpro_smtp_server" "graph_api" {
  enabled             = true
  authentication_type = "GRAPH_API"

  sender_settings {
    email_address = "noreply@yourdomain.onmicrosoft.com"
  }

  graph_api_credentials {
    tenant_id     = "c84b7b82-c277-411b-975d-7431b4ce40ac"
    client_id     = "5294f9d1-f723-419c-93db-ff040bf7c947"
    client_secret = "password"
  }
}
