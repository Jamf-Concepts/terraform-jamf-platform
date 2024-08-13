data "http" "profile" {
  url = "http://${aws_eip.ElasticIP.public_ip}/download"

  # Retry block to handle retries
  retry {
    attempts     = 10    # Number of retry attempts
    min_delay_ms = 20000 # 20 seconds between retries
  }
}




resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_profile_SaaSTenCert" {
  name                = "SaaS Tenancy Cert"
  description         = "An example mobile device configuration profile."
  level               = "System"                // "User", "Device"
  distribution_method = "Install Automatically" // "Make Available in Self Service", "Install Automatically"
  payloads            = trimspace(data.http.profile.response_body)
  payload_validate    = false

  user_removable = false

  scope {
    all_computers = true
  }

  lifecycle {
    precondition {
      condition     = contains([200, 204], data.http.profile.status_code)
      error_message = "Status code invalid"
    }
  }


}

output "profile" {
  value = data.http.profile.response_body
}


output "profilestatuscode" {
  value = data.http.profile.status_code
}


