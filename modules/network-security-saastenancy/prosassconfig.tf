data "http" "profile" {
  url = "http://${aws_eip.ElasticIP.public_ip}/download"

  # Retry block to handle retries
  retry {
    attempts     = 10    # Number of retry attempts
    min_delay_ms = 20000 # 20 seconds between retries
  }
}




resource "jamfplatform_pro_macos_configuration_profile" "jamfpro_macos_configuration_profile_SaaSTenCert" {


  lifecycle {
    precondition {
      condition     = contains([200, 204], data.http.profile.status_code)
      error_message = "Status code invalid"
    }
  }


  general = {
    name                = "SaaS Tenancy Cert"
    description         = "An example mobile device configuration profile."
    level               = "Computer Level"
    distribution_method = "Install Automatically"
    payloads            = trimspace(data.http.profile.response_body)
    redeploy_on_update  = "Newly Assigned"
    user_removable      = false
  }
  scope = {
    targets = {
      all_computers = true
    }
  }
}

output "profile" {
  value = data.http.profile.response_body
}


output "profilestatuscode" {
  value = data.http.profile.status_code
}

