# Onboarder Modules
module "onboarder-all" {
  count                       = var.include_onboarder_all == true ? 1 : 0
  source                      = "./modules/onboarder-all"
  jamfplatform_base_url       = var.jamfplatform_base_url
  jamfplatform_client_id      = var.jamfplatform_client_id
  jamfplatform_client_secret  = var.jamfplatform_client_secret
  jamfprotect_url             = var.jamfprotect_url
  jamfprotect_client_id       = var.jamfprotect_client_id
  jamfprotect_client_password = var.jamfprotect_client_password
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}

module "onboarder-management-macOS" {
  count  = var.include_onboarder_management_macOS == true ? 1 : 0
  source = "./modules/onboarder-management-macOS"
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "onboarder-management-mobile" {
  count  = var.include_onboarder_management_mobile == true ? 1 : 0
  source = "./modules/onboarder-management-mobile"
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "onboarder-app-installers" {
  count  = var.include_onboarder_app_installers == true ? 1 : 0
  source = "./modules/onboarder-app-installers"
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

## Initialize Protect (for macOS) module

module "configuration-jamf-pro-jamf-protect" {
  count                       = var.include_jamf_protect_trial_kickstart == true ? 1 : 0
  source                      = "./modules/configuration-jamf-pro-jamf-protect"
  jamfplatform_base_url       = var.jamfplatform_base_url
  jamfplatform_client_id      = var.jamfplatform_client_id
  jamfplatform_client_secret  = var.jamfplatform_client_secret
  jamfprotect_url             = var.jamfprotect_url
  jamfprotect_client_id       = var.jamfprotect_client_id
  jamfprotect_client_password = var.jamfprotect_client_password
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-macOS-cis-level-1" {
  count                      = var.include_mac_cis_lvl1_benchmark == true ? 1 : 0
  source                     = "./modules/compliance-macOS-cis-level-1"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-macOS-cbengine-benchmark" {
  count                      = var.mac_cbengine_baseline_id != "" ? 1 : 0
  source                     = "./modules/compliance-macOS-cbengine-benchmark"
  baseline_id                = var.mac_cbengine_baseline_id
  benchmark_title            = var.mac_cbengine_baseline_title != "" ? var.mac_cbengine_baseline_title : var.mac_cbengine_baseline_id
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-macOS-software-update-blueprint" {
  count                      = var.include_mac_software_update_blueprint == true ? 1 : 0
  source                     = "./modules/management-macOS-software-update-blueprint"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-iOS-cis-level-1" {
  count                      = var.include_mobile_cis_lvl1_benchmark == true ? 1 : 0
  source                     = "./modules/compliance-iOS-cis-level-1"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-macOS-disa-stig" {
  count                      = var.include_mac_stig_benchmark == true ? 1 : 0
  source                     = "./modules/compliance-macOS-disa-stig"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-iOS-disa-stig" {
  count                      = var.include_mobile_stig_benchmark == true ? 1 : 0
  source                     = "./modules/compliance-iOS-disa-stig"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-macOS-nist-800-171" {
  count                      = var.include_mac_800_171_benchmark == true ? 1 : 0
  source                     = "./modules/compliance-macOS-nist-800-171"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "compliance-macOS-cmmc-level-1" {
  count                      = var.include_mac_cmmc_lvl1_benchmark == true ? 1 : 0
  source                     = "./modules/compliance-macOS-cmmc-level-1"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-pro-admin-sso" {
  count                      = var.include_jamf_pro_admin_sso == true ? 1 : 0
  source                     = "./modules/configuration-jamf-pro-admin-sso"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-pro-activation-code" {
  count                      = var.include_jamf_pro_activation_code == true ? 1 : 0
  source                     = "./modules/configuration-jamf-pro-activation-code"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  organization_name          = var.organization_name
  jamf_pro_activation_code   = var.jamf_pro_activation_code
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-pro-smart-groups" {
  count                      = var.include_qol_smart_groups == true ? 1 : 0
  source                     = "./modules/configuration-jamf-pro-smart-groups"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-macOS-microsoft-365" {
  count                      = var.include_microsoft_365 == true ? 1 : 0
  source                     = "./modules/management-macOS-microsoft-365"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-pro-categories" {
  count                      = var.include_categories == true ? 1 : 0
  source                     = "./modules/configuration-jamf-pro-categories"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-iOS-configuration-profiles" {
  count                      = var.include_mobile_device_kickstart == true ? 1 : 0
  source                     = "./modules/management-iOS-configuration-profiles"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "configuration-jamf-pro-computer-management-settings" {
  count                      = var.include_computer_management_settings == true ? 1 : 0
  source                     = "./modules/configuration-jamf-pro-computer-management-settings"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

# Workbrew Stage 1: Create API Role and Integration (deploy first, get credentials)
module "configuration-jamf-pro-api-role-client-workbrew" {
  count                      = var.include_workbrew_api_role_client == true ? 1 : 0
  source                     = "./modules/configuration-jamf-pro-api-role-client-workbrew"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

# Workbrew Stage 2: Deploy management resources (after uploading credentials to Workbrew Console)
module "management-macOS-workbrew" {
  count                      = var.include_workbrew == true ? 1 : 0
  source                     = "./modules/management-macOS-workbrew"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  workbrew_workspace_api_key = var.workbrew_workspace_api_key
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "endpoint-security-macOS-filevault" {
  count                      = var.include_filevault == true ? 1 : 0
  source                     = "./modules/endpoint-security-macOS-filevault"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "endpoint-security-macOS-microsoft-defender" {
  count                          = var.include_defender == true ? 1 : 0
  source                         = "./modules/endpoint-security-macOS-microsoft-defender"
  jamfplatform_base_url          = var.jamfplatform_base_url
  jamfplatform_client_id         = var.jamfplatform_client_id
  jamfplatform_client_secret     = var.jamfplatform_client_secret
  defender_onboarding_plist_path = var.defender_onboarding_plist_path
  defender_onboarding_plist      = var.defender_onboarding_plist
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-macOS-SSOe-Okta" {
  count                      = var.include_ssoe_okta == true ? 1 : 0
  source                     = "./modules/management-macOS-SSOe-Okta"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-okta_psso" {
  count                      = var.include_okta_psso == true ? 1 : 0
  source                     = "./modules/management-okta-psso"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  okta_short_url             = var.okta_short_url
  okta_org_name              = var.okta_org_name
  okta_scep_url              = var.okta_scep_url
  okta_psso_client           = var.okta_psso_client
  okta_scep_username         = var.okta_scep_username
  okta_scep_password         = var.okta_scep_password
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-microsoft_psso" {
  count                      = var.include_microsoft_psso == true ? 1 : 0
  source                     = "./modules/management-microsoft-psso"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "endpoint-security-macOS-crowdstrike" {
  count                      = var.include_crowdstrike == true ? 1 : 0
  source                     = "./modules/endpoint-security-macOS-crowdstrike"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  falcon_api_client_id       = var.falcon_api_client_id
  falcon_api_secret          = var.falcon_api_secret
  falcon_customer_id         = var.falcon_customer_id
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-macOS-rosetta" {
  count                      = var.include_rosetta == true ? 1 : 0
  source                     = "./modules/management-macOS-rosetta"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-app-installers" {
  source                     = "./modules/management-app-installers"
  for_each                   = toset(var.app_installers)
  app_installer_name         = each.value
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

module "management-app-installers-google-chrome-cloud-management" {
  count                                           = var.include_google_chrome_cloud_management == true ? 1 : 0
  source                                          = "./modules/management-app-installers-google-chrome-cloud-management"
  jamfplatform_base_url                           = var.jamfplatform_base_url
  jamfplatform_client_id                          = var.jamfplatform_client_id
  jamfplatform_client_secret                      = var.jamfplatform_client_secret
  include_google_chrome                           = var.include_google_chrome
  app_installers                                  = var.app_installers
  google_chrome_cloud_management_enrollment_token = var.google_chrome_cloud_management_enrollment_token
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

## Begin Jamf Security Cloud Configuration

## Create UEMC and Okta integrations
module "configuration-jamf-security-cloud-jamf-pro" {
  count                      = var.include_jsc_uemc == true ? 1 : 0
  source                     = "./modules/configuration-jamf-security-cloud-jamf-pro"
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfpro_instance_url       = var.jamfpro_instance_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
  }
}

## Create Jamf Security Cloud Activation Profile containing ALL JSC Services
module "configuration-jamf-security-cloud-all-services" {
  count                      = var.include_jsc_all_services == true ? 1 : 0
  source                     = "./modules/configuration-jamf-security-cloud-all-services"
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}

module "network-security-access-policy" {
  source             = "./modules/network-security-access-policy"
  for_each           = toset(var.access_policies)
  access_policy_name = each.value
  jsc_username       = var.jsc_username
  jsc_password       = var.jsc_password
  providers = {
    jsc.jsc = jsc.jsc
  }
}

module "configuration-jamf-security-cloud-block-pages" {
  count           = var.include_jsc_block_pages == true ? 1 : 0
  source          = "./modules/configuration-jamf-security-cloud-block-pages"
  block_page_logo = var.block_page_logo
  jsc_username    = var.jsc_username
  jsc_password    = var.jsc_password
  providers = {
    jsc.jsc = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Category Based Content Filtering
module "network-security-jamf-pro-content-filtering" {
  count                      = var.include_jsc_dp_only == true ? 1 : 0
  source                     = "./modules/network-security-jamf-pro-content-filtering"
  okta_client_id             = var.okta_client_id
  okta_org_domain            = var.okta_org_domain
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Threat Response (MTD)
module "network-security-jamf-pro-network-threat-defense" {
  count                      = var.include_jsc_mtd_only == true ? 1 : 0
  source                     = "./modules/network-security-jamf-pro-network-threat-defense"
  okta_client_id             = var.okta_client_id
  okta_org_domain            = var.okta_org_domain
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing Content Filtering + MTD
module "network-security-jamf-pro-content-filtering-and-network-threat-defense" {
  count                      = var.include_jsc_mtd_dp_only == true ? 1 : 0
  source                     = "./modules/network-security-jamf-pro-content-filtering-and-network-threat-defense"
  okta_client_id             = var.okta_client_id
  okta_org_domain            = var.okta_org_domain
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Connect ZTNA
module "network-security-jamf-pro-zero-trust-network-access" {
  count                      = var.include_jsc_ztna == true ? 1 : 0
  source                     = "./modules/network-security-jamf-pro-zero-trust-network-access"
  okta_client_id             = var.okta_client_id
  okta_org_domain            = var.okta_org_domain
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ZTNA + Content Filtering
module "network-security-jamf-pro-zero-trust-network-access-and-content-filtering" {
  count                      = var.include_jsc_ztna_dp_only == true ? 1 : 0
  source                     = "./modules/network-security-jamf-pro-zero-trust-network-access-and-content-filtering"
  okta_client_id             = var.okta_client_id
  okta_org_domain            = var.okta_org_domain
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ZTNA + MTD
module "network-security-jamf-pro-zero-trust-network-access-and-network-threat-prevention" {
  count                      = var.include_jsc_ztna_mtd_only == true ? 1 : 0
  source                     = "./modules/network-security-jamf-pro-zero-trust-network-access-and-network-threat-prevention"
  okta_client_id             = var.okta_client_id
  okta_org_domain            = var.okta_org_domain
  jsc_username               = var.jsc_username
  jsc_password               = var.jsc_password
  jamfplatform_base_url      = var.jamfplatform_base_url
  jamfplatform_client_id     = var.jamfplatform_client_id
  jamfplatform_client_secret = var.jamfplatform_client_secret
  providers = {
    jamfplatform.jpro = jamfplatform.jpro
    jsc.jsc           = jsc.jsc
  }
}
