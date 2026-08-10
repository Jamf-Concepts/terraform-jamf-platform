## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.26.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Create Categories
resource "jamfplatform_pro_category" "category_crowdstrike" {
  name     = "Crowdstrike"
  priority = 9
}

## Create Scripts
resource "jamfplatform_pro_script" "scripts_falconpkg" {
  name            = "Falcon Sensor API Install"
  os_requirements = "0"
  priority        = "AFTER"
  info            = "Source: https://github.com/franton/Crowdstrike-API-Scripts/blob/main/install-csf.sh"
  notes           = ""
  script_contents          = file("${path.module}/support_files/scripts/falconinstall.sh")
  parameter_4     = "FALCON API CLIENT ID"
  parameter_5     = "FALCON API SECRET"
  parameter_6     = ""
  parameter_7     = ""
}

resource "jamfplatform_pro_script" "scripts_falconcid" {
  name            = "Falcon CID"
  os_requirements = "0"
  priority        = "AFTER"
  info            = ""
  notes           = ""
  script_contents          = file("${path.module}/support_files/scripts/falconcid.sh")
  parameter_4     = "FALCON CUSTOMER ID"
  parameter_5     = ""
  parameter_6     = ""
  parameter_7     = ""
}


## Crowdstrke PPPC, Content Filtering, System Extension, 
resource "jamfplatform_pro_macos_configuration_profile" "jamfpro_macos_configuration_crowdstrike" {

  general = {
    name                = "Crowdstrike Falcon Settings"
    description         = ""
    level               = "Computer Level"
    category_id         = jamfplatform_pro_category.category_crowdstrike.id
    redeploy_on_update  = "Newly Assigned"
    distribution_method = "Install Automatically"
    payloads            = file("${path.module}/support_files/falcon.mobileconfig")
    user_removable      = false
  }
  scope = {
    targets = {
      all_computers = true
    }
  }
}

## Create Crowdsrike Install Policy
resource "jamfplatform_pro_policy" "policy_crowdstrike_api_install" {




  general = {
    name            = "Crowdstrike Falcon API Install"
    enabled         = true
    trigger_checkin = "true"
    frequency       = "Once per computer"
    category_id     = jamfplatform_pro_category.category_crowdstrike.id
  }
  scope = {
    targets = {
      all_computers = true
    }
  }
  self_service = {
    use_for_self_service            = false
    self_service_display_name       = ""
    install_button_text             = ""
    self_service_description        = ""
    force_users_to_view_description = false
    feature_on_main_page            = false
  }
  scripts = {
    scripts = [
      {
        id         = jamfplatform_pro_script.scripts_falconcid.id
        priority   = "After"
        parameter4 = var.falcon_customer_id
        parameter5 = ""
        parameter6 = ""
      },
    ]
  }
  maintenance = {
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
