## Jamf Pro provider root configuration
provider "jamfpro" {
  jamfpro_instance_fqdn                = var.jamfpro_instance_url
  auth_method                          = var.jamfpro_auth_method
  basic_auth_username                  = var.jamfpro_username
  basic_auth_password                  = var.jamfpro_password
  client_id                            = var.jamfpro_client_id
  client_secret                        = var.jamfpro_client_secret
  enable_client_sdk_logs               = false
  hide_sensitive_data                  = true # Hides sensititve data in logs
  token_refresh_buffer_period_seconds  = 5    # minutes
  jamfpro_load_balancer_lock           = true
  mandatory_request_delay_milliseconds = 100
}

# JSC provider root configuration
provider "jsc" {
  username          = var.jsc_username
  password          = var.jsc_password
  applicationid     = var.jsc_applicationid
  applicationsecret = var.jsc_applicationsecret
}

## Uncomment the lines below to add a random identifier to the end of each item created by these modules. This helps prevent run-ins with duplicate resources being created. 
## These are commented out by default for use in Onboarder as a one time apply does not need identifiers.
## ---------------------------------------------------------------
# resource "random_integer" "entropy" {
#   min = 10
#   max = 999
# }

# locals {
#   entropy_string = "[Run ID # ${random_integer.entropy.result}]"
# }
## ---------------------------------------------------------------

# Onboarder Modules
module "onboarder-all" {
  count          = var.include_onboarder_all == true ? 1 : 0
  source         = "./modules/onboarder-all"
  entropy_string = var.entropy_string
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

module "onboarder-management-macOS" {
  count          = var.include_onboarder_management_macOS == true ? 1 : 0
  source         = "./modules/onboarder-management-macOS"
  entropy_string = var.entropy_string
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "onboarder-management-mobile" {
  count          = var.include_onboarder_management_mobile == true ? 1 : 0
  source         = "./modules/onboarder-management-mobile"
  entropy_string = var.entropy_string
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "onboarder-app-installers" {
  count          = var.include_onboarder_app_installers == true ? 1 : 0
  source         = "./modules/onboarder-app-installers"
  entropy_string = var.entropy_string
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

## Initialize common modules

## Initialize Protect (for macOS) module

module "configuration-jamf-pro-jamf-protect" {
  count                       = var.include_jamf_protect_trial_kickstart == true ? 1 : 0
  source                      = "./modules/configuration-jamf-pro-jamf-protect"
  entropy_string              = var.entropy_string
  jamfpro_instance_url        = var.jamfpro_instance_url
  jamfpro_client_id           = var.jamfpro_client_id
  jamfpro_client_secret       = var.jamfpro_client_secret
  jamfprotect_url             = var.jamfprotect_url
  jamfprotect_clientID        = var.jamfprotect_clientID
  jamfprotect_client_password = var.jamfprotect_client_password
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-macOS-cis-level-1" {
  count                 = var.include_mac_cis_lvl1_benchmark == true ? 1 : 0
  source                = "./modules/compliance-macOS-cis-level-1"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-iOS-cis-level-1" {
  count                 = var.include_mobile_cis_lvl1_benchmark == true ? 1 : 0
  source                = "./modules/compliance-iOS-cis-level-1"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-macOS-disa-stig" {
  count                 = var.include_mac_stig_benchmark == true ? 1 : 0
  source                = "./modules/compliance-macOS-disa-stig"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-iOS-disa-stig" {
  count                 = var.include_mobile_stig_benchmark == true ? 1 : 0
  source                = "./modules/compliance-iOS-disa-stig"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-macOS-nist-800-171" {
  count                 = var.include_mac_800_171_benchmark == true ? 1 : 0
  source                = "./modules/compliance-macOS-nist-800-171"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "compliance-macOS-cmmc-level-1" {
  count                 = var.include_mac_cmmc_lvl1_benchmark == true ? 1 : 0
  source                = "./modules/compliance-macOS-cmmc-level-1"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "configuration-jamf-pro-admin-sso" {
  count                 = var.include_jamf_pro_admin_sso == true ? 1 : 0
  source                = "./modules/configuration-jamf-pro-admin-sso"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "configuration-jamf-pro-smart-groups" {
  count                 = var.include_qol_smart_groups == true ? 1 : 0
  source                = "./modules/configuration-jamf-pro-smart-groups"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "management-macOS-microsoft-365" {
  count                 = var.include_microsoft_365 == true ? 1 : 0
  source                = "./modules/management-macOS-microsoft-365"
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "configuration-jamf-pro-categories" {
  count                 = var.include_categories == true ? 1 : 0
  source                = "./modules/configuration-jamf-pro-categories"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "management-iOS-configuration-profiles" {
  count                 = var.include_mobile_device_kickstart == true ? 1 : 0
  source                = "./modules/management-iOS-configuration-profiles"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "configuration-jamf-pro-computer-management-settings" {
  count                 = var.include_computer_management_settings == true ? 1 : 0
  source                = "./modules/configuration-jamf-pro-computer-management-settings"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "endpoint-security-macOS-filevault" {
  count                 = var.include_filevault == true ? 1 : 0
  source                = "./modules/endpoint-security-macOS-filevault"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "endpoint-security-macOS-microsoft-defender" {
  count                 = var.include_defender == true ? 1 : 0
  source                = "./modules/endpoint-security-macOS-microsoft-defender"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "management-macOS-SSOe-Okta" {
  count                 = var.include_ssoe_okta == true ? 1 : 0
  source                = "./modules/management-macOS-SSOe-Okta"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "endpoint-security-macOS-crowdstrike" {
  count                 = var.include_crowdstrike == true ? 1 : 0
  source                = "./modules/endpoint-security-macOS-crowdstrike"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  falcon_api_client_id  = "placeholderclientID"
  falcon_api_secret     = "placeholderclientsecret"
  falcon_customer_id    = "placeholdercustomerID"
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "management-macOS-rosetta" {
  count                 = var.include_rosetta == true ? 1 : 0
  source                = "./modules/management-macOS-rosetta"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

module "management-app-installers" {
  source                = "./modules/management-app-installers"
  entropy_string        = var.entropy_string
  for_each              = toset(var.app_installers)
  app_installer_name    = each.value
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
  }
}

## Begin Jamf Security Cloud Configuration

## Create UEMC and Okta integrations
module "configuration-jamf-security-cloud-jamf-pro" {
  count                 = var.include_jsc_uemc == true ? 1 : 0
  source                = "./modules/configuration-jamf-security-cloud-jamf-pro"
  entropy_string        = var.entropy_string
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ALL JSC Services
module "configuration-jamf-security-cloud-all-services" {
  count                 = var.include_jsc_all_services == true ? 1 : 0
  source                = "./modules/configuration-jamf-security-cloud-all-services"
  entropy_string        = var.entropy_string
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

module "network-security-access-policy" {
  source             = "./modules/network-security-access-policy"
  entropy_string     = var.entropy_string
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
  entropy_string  = var.entropy_string
  block_page_logo = var.block_page_logo
  jsc_username    = var.jsc_username
  jsc_password    = var.jsc_password
  providers = {
    jsc.jsc = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Category Based Content Filtering
module "network-security-jamf-pro-content-filtering" {
  count                 = var.include_jsc_dp_only == true ? 1 : 0
  source                = "./modules/network-security-jamf-pro-content-filtering"
  entropy_string        = var.entropy_string
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Threat Response (MTD)
module "network-security-jamf-pro-network-threat-defense" {
  count                 = var.include_jsc_mtd_only == true ? 1 : 0
  source                = "./modules/network-security-jamf-pro-network-threat-defense"
  entropy_string        = var.entropy_string
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Threat Response (MTD)
module "network-security-jamf-pro-content-filtering-and-network-threat-defense" {
  count                 = var.include_jsc_mtd_dp_only == true ? 1 : 0
  source                = "./modules/network-security-jamf-pro-content-filtering-and-network-threat-defense"
  entropy_string        = var.entropy_string
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Connect ZTNA
module "network-security-jamf-pro-zero-trust-network-access" {
  count                 = var.include_jsc_ztna == true ? 1 : 0
  source                = "./modules/network-security-jamf-pro-zero-trust-network-access"
  entropy_string        = var.entropy_string
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Connect ZTNA
module "network-security-jamf-pro-zero-trust-network-access-and-content-filtering" {
  count                 = var.include_jsc_ztna_dp_only == true ? 1 : 0
  source                = "./modules/network-security-jamf-pro-zero-trust-network-access-and-content-filtering"
  entropy_string        = var.entropy_string
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}

## Create Jamf Security Cloud Activation Profile containing ONLY Connect ZTNA
module "network-security-jamf-pro-zero-trust-network-access-and-network-threat-prevention" {
  count                 = var.include_jsc_ztna_mtd_only == true ? 1 : 0
  source                = "./modules/network-security-jamf-pro-zero-trust-network-access-and-network-threat-prevention"
  entropy_string        = var.entropy_string
  tje_okta_clientid     = var.tje_okta_clientid
  tje_okta_orgdomain    = var.tje_okta_orgdomain
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  jamfpro_instance_url  = var.jamfpro_instance_url
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}
