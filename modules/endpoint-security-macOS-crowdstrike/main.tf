## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Create Categories
resource "jamfpro_category" "category_crowdstrike" {
  name     = "Crowdstrike"
  priority = 9
}

## Create Scripts
resource "jamfpro_script" "scripts_falconpkg" {
  name            = "Falcon Sensor API Install"
  script_contents = file("${path.module}/support_files/scripts/falconinstall.sh")
  category_id     = jamfpro_category.category_crowdstrike.id
  os_requirements = "0"
  priority        = "AFTER"
  info            = "Source: https://github.com/franton/Crowdstrike-API-Scripts/blob/main/install-csf.sh"
  notes           = ""
  parameter4      = "FALCON API CLIENT ID"
  parameter5      = "FALCON API SECRET"
  parameter6      = ""
  parameter7      = ""
}

resource "jamfpro_script" "scripts_falconcid" {
  name            = "Falcon CID"
  script_contents = file("${path.module}/support_files/scripts/falconcid.sh")
  category_id     = jamfpro_category.category_crowdstrike.id
  os_requirements = "0"
  priority        = "AFTER"
  info            = ""
  notes           = ""
  parameter4      = "FALCON CUSTOMER ID"
  parameter5      = ""
  parameter6      = ""
  parameter7      = ""
}


## Crowdstrke PPPC, Content Filtering, System Extension, 
resource "jamfpro_macos_configuration_profile_plist" "jamfpro_macos_configuration_crowdstrike" {
  name                = "Crowdstrike Falcon Settings"
  description         = ""
  level               = "System"
  category_id         = jamfpro_category.category_crowdstrike.id
  redeploy_on_update  = "Newly Assigned"
  distribution_method = "Install Automatically"
  payloads            = file("${path.module}/support_files/falcon.mobileconfig")
  payload_validate    = false
  user_removable      = false

  scope {
    all_computers = true
    all_jss_users = false
  }
}

## Create Crowdsrike Install Policy
resource "jamfpro_policy" "policy_crowdstrike_api_install" {
  name            = "Crowdstrike Falcon API Install"
  enabled         = true
  trigger_checkin = "true"
  frequency       = "Once per computer"
  category_id     = jamfpro_category.category_crowdstrike.id


  scope {
    all_computers = true
  }

  self_service {
    use_for_self_service            = false
    self_service_display_name       = ""
    install_button_text             = ""
    self_service_description        = ""
    force_users_to_view_description = false
    feature_on_main_page            = false
  }

  payloads {
    scripts {
      id         = jamfpro_script.scripts_falconpkg.id
      priority   = "Before"
      parameter4 = var.falcon_api_client_id
      parameter5 = var.falcon_api_secret
      parameter6 = ""
    }
    scripts {
      id         = jamfpro_script.scripts_falconcid.id
      priority   = "After"
      parameter4 = var.falcon_customer_id
      parameter5 = ""
      parameter6 = ""
    }


    maintenance {
      recon                       = true
      reset_name                  = false
      install_all_cached_packages = false
      heal                        = false
      prebindings                 = false
      permissions                 = false
      byhost                      = false
      system_cache                = false
      user_cache                  = false
      verify                      = false
    }
  }
}
