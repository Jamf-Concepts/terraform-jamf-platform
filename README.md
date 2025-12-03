# terraform-jamf-platform

Terraform configuration for the Jamf Platform.

Provider versions used in this release:

- deploymenttheory/jamfpro = v0.19.1
- Jamf-Concepts/jsctfprovider >= v0.0.23
- hasicorp/aws v55.62.0 (optional with SaaS tenancy control)

This project utlizes the community Terraform providers for [Jamf Pro](https://registry.terraform.io/providers/deploymenttheory/jamfpro/latest) and [Jamf Security Cloud](https://registry.terraform.io/providers/Jamf-Concepts/jsctfprovider/latest)

## Parallelism and API delay

Lowering Terraform parallelism from 10 to 1 reduces the chances of API call errors. Run this command before applying your configuration

```
export TF_CLI_ARGS_apply="-parallelism=1"
```

We also recommend setting the `mandatory_request_delay_milliseconds`provider key to 100.

# Running Included Modules

The modules included here are using aliased calls to the Jamf Pro and Jamf Security Cloud providers that are used. This is done to ensure that you only need credentials for the module you are running. 

To run these successfully in your environment, include the following:

1. In your root main.tf file, add the required providers
2. Add the Provider configs for your required provider. Change whatever is needed but make sure to leave the ```alias``` variable. Here's are examples for both included providers:
```
## Jamf Pro provider root configuration
provider "jamfpro" {
  alias                                = "jpro"
  jamfpro_instance_fqdn                = var.jamfpro_instance_fqdn
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
  alias             = "jsc"
  username          = var.jsc_username
  password          = var.jsc_password
  applicationid     = var.jsc_applicationid
  applicationsecret = var.jsc_applicationsecret
}
```
3. Add a ```providers``` block to each sub-module call. Here's an example:
```
module "configuration-jamf-security-cloud-jamf-pro" {
  source                = "module/source/file/path"
  jamfpro_instance_fqdn  = var.jamfpro_instance_fqdn
  jamfpro_client_id     = var.jamfpro_client_id
  jamfpro_client_secret = var.jamfpro_client_secret
  jsc_username          = var.jsc_username
  jsc_password          = var.jsc_password
  providers = {
    jamfpro.jpro = jamfpro.jpro
    jsc.jsc      = jsc.jsc
  }
}
```
4. Sub-modules will need to call the required provider slightly differently. 
### Normal method - (also used for your root main.tf):
```
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = "0.19.1"
    }
    jsc = {
      source  = "Jamf-Concepts/jsctfprovider"
      version = ">= 0.0.23"
    }
  }
}
```
### Revised method for sub-modules:
```
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
    jsc = {
      source                = "Jamf-Concepts/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}
```

## Variables definition

This Terraform project requires Jamf API credentials and other context-specific variables that you'll need to define locally in a terraform.tfvars file.

```
cd /Users/[FIRST.LAST]/PATH
nano terraform.tfvars
```

Copy and paste the following data then customize it with your own credentials and set knobs to enable specific modules contained within this project.

```
## Jamf Pro Account Details
jamfpro_auth_method   = "" ## oauth2 or basic
jamfpro_instance_fqdn  = ""
jamfpro_client_id     = ""
jamfpro_client_secret = ""
jamfpro_username      = ""
jamfpro_password      = ""

## Jamf Protect Account Details
jamfprotect_url             = ""
jamfprotect_client_id        = ""
jamfprotect_client_password = ""

## Jamf Security Cloud (RADAR) Account Details
jsc_username          = ""
jsc_password          = ""
jsc_applicationid     = ""
jsc_applicationsecret = ""

## tryjamf Okta Account Details
okta_client_id  = ""
okta_org_domain = ""

##################################
##### ONBOARDER MODULE KNOBS #####
##################################

## (Jamf Pro) General Settings Knobs ##
include_jamf_pro_admin_sso           = false
include_qol_smart_groups             = false
include_categories                   = false
include_computer_management_settings = false

## (Jamf Pro) Compliance Benchmark Knobs
include_mac_cis_lvl1_benchmark    = false
include_mobile_cis_lvl1_benchmark = false
include_mac_stig_benchmark        = false
include_mobile_stig_benchmark     = false
include_mac_800_171_benchmark     = false
include_mac_cmmc_lvl1_benchmark   = false

## (Jamf Pro) Computer Outcome Knobs
include_microsoft_365 = false
include_filevault     = false
include_rosetta       = false
include_ssoe_okta     = false

## (Jamf Pro) Mobile Outcome Knobs
include_mobile_device_kickstart = false

## (Jamf Pro) App Installer Knobs
include_google_chrome        = false
include_mozilla_firefox      = false
include_slack                = false
include_dropbox              = false
include_google_drive         = false
include_jamf_composer        = false
include_pppc_utility         = false
include_jamfcheck            = false
include_zoom                 = false
include_adobe_creative_cloud = false
include_box_drive            = false
include_microsoft_edge       = false
include_text_expander        = false
include_nudge                = false
app_installers               = []

## Jamf Protect Knobs ##
include_jamf_protect_trial_kickstart = false

## Jamf Security Cloud Knobs ##
include_jsc_block_pages   = false
include_jsc_all_services  = false
include_jsc_network_relay = false
include_jsc_uemc          = false
include_jsc_ap_adobe      = false
include_jsc_ap_atlassian  = false
include_jsc_ap_bluejeans  = false
include_jsc_ap_box        = false
include_jsc_ap_docusign   = false
include_jsc_ap_dropbox    = false
include_jsc_ap_github     = false
include_jsc_ap_google     = false
include_jsc_ap_hubspot    = false
include_jsc_ap_mailchimp  = false
include_jsc_ap_mathworks  = false
include_jsc_ap_microsoft  = false
include_jsc_ap_my_ip      = false
include_jsc_ap_okta       = false
include_jsc_ap_salesforce = false
include_jsc_ap_servicenow = false
include_jsc_ap_slack      = false
include_jsc_ap_snowflake  = false
include_jsc_ap_splunk     = false
include_jsc_ap_square     = false
include_jsc_ap_twilio     = false
include_jsc_ap_webex      = false
include_jsc_ap_workday    = false
include_jsc_ap_zendesk    = false
include_jsc_ap_zoom       = false

```

Save and exit.

## Usage

Ensure that you are in the correct project folder when performing Terraform commands, ie.,

```
/Users/[FIRST.LAST]/PATH/
```

Before applying any terraform modules you must initialize the providers being called. It's a good idea to run this before the first apply of your session

```
terraform init -upgrade
```

Terraform must be formatted correctly to run, which can be done manually after saving changes before each run with `terraform fmt`. If using Visual Studio Code, use [this guide](https://medium.com/nerd-for-tech/how-to-auto-format-hcl-terraform-code-in-visual-studio-code-6fa0e7afbb5e) to never have to run the format command again!

< INSERT INSTRUCTIONS FOR RUNNING TERRAFORM MODULES>
