# terraform-jamf-platform

Terraform configuration for the Jamf Platform.

Provider versions used in this release:

- deploymenttheory/jamfpro > = v0.11.0
- danjamf/jsctfprovider >= v0.0.23
- hasicorp/aws v55.62.0 (optional with SaaS tenancy control)

This project utlizes the unoffical Terraform providers for [Jamf Pro](https://registry.terraform.io/providers/deploymenttheory/jamfpro/latest) and [Jamf Security Cloud](https://registry.terraform.io/providers/danjamf/jsctfprovider/latest)

## Parallelism and API delay

Lowering Terraform parallelism from 10 to 1 reduces the chances of API call errors. Run this command before applying your configuration

```
export TF_CLI_ARGS_apply="-parallelism=1"
```

We also recommend setting the `mandatory_request_delay_milliseconds`provider key to 100.

## Variables definition

This Terraform project requires Jamf API credentials and other context-specific variables that you'll need to define locally in a terraform.tfvars file.

```
cd /Users/[FIRST.LAST]/PATH
nano terraform.tfvars
```

Copy and paste the following data then customize it with your own credentials and set knobs to enable specific modules contained within this project.

```
## Jamf Pro Account Details
jamfpro_instance_url  = ""
jamfpro_auth_method   = "oauth2"
jamfpro_client_id     = ""
jamfpro_client_secret = ""


## Jamf Security Cloud (RADAR) Account Details
jsc_username          = ""
jsc_password          = ""
jsc_applicationid     = ""
jsc_applicationsecret = ""
block_page_logo       = ""
## block_page_logo takes a Base 64 encoded string conversion of the image only

## tryjamf Okta Account Details
tje_okta_clientid  = ""
tje_okta_orgdomain = ""



# File path prefix for Terraform directory
support_files_path_prefix = "" ## Path to your directory - example: /Users/<youruser>/filename/

##################################
##### MODULE KNOBS #####
##################################


## (Jamf Pro) General Settings Knobs ##
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
include_microsoft_365          = false
include_filevault              = false
include_rosetta                = false
include_passwordless_ssoe      = false

## (Jamf Pro) Mobile Outcome Knobs
include_mobile_device_kickstart      = false

## (Jamf Pro) App Installer Knobs
include_google_chrome   = false
include_mozilla_firefox = false
include_slack           = false
include_dropbox         = false
include_google_drive    = false
include_jamf_composer   = false
include_pppc_utility    = false
include_jamfcheck       = false
include_zoom            = false

## Jamf Protect Knobs ##
include_jamf_protect_trial_kickstart = false

## Jamf Security Cloud Knobs ##
include_jsc_block_pages   = false
include_jsc_all_services  = false
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

############################################

##################################
##### MISC MODULE KNOBS ##########
##################################

##### NOT INCLUDED IN SPEC.YAML ###

## Jamf Security Cloud Knobs ##
include_jsc_dp_only       = false
include_jsc_mtd_only      = false
include_jsc_ztna          = false
include_jsc_network_relay = false
include_jsc_mtd_dp_only   = false
include_jsc_ztna_dp_only  = false
include_jsc_ztna_mtd_only = false


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

Enter the following command to apply full Terraform config:

```
terraform apply
```

Enter this command to only apply specific modules:

```
terraform apply -target "module.[MODULE_NAME]"
```

By default all modules will be applied. You can unselect individual modules by modifing the module knobs in your tfvars file e.g.

```
mac_cis_lvl1_benchmark = false
```
