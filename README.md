# terraform-jamf-platform

Terraform configuration for the Jamf Platform.

This project utlizes the community Terraform providers for [Jamf Pro](https://registry.terraform.io/providers/deploymenttheory/jamfpro/latest) and [Jamf Security Cloud](https://registry.terraform.io/providers/Jamf-Concepts/jsctfprovider/latest)

## Parallelism and API delay

Lowering Terraform parallelism from 10 to 1 reduces the chances of API call errors. Run this command before applying your configuration

```
terraform apply -parallelism=1
```

## Variables definition

This Terraform project requires Jamf API credentials and other context-specific variables that you'll need to define locally in a terraform.tfvars file.

```
cd /Users/[FIRST.LAST]/PATH
nano terraform.tfvars
```

* NOTE: If you need to create an API Client in your Jamf Pro to enable this functionality, please use the script found at ```tools/JamfPro-API_create-role-client_prompt-for-permissions.sh``` to do so. 

## Configuration

Copy and paste the following data then customize it with your own credentials and set knobs to enable specific modules contained within this project.

```
## Jamf Pro Account Details
jamfpro_auth_method   = "" ## oauth2 or basic
jamfpro_instance_url  = ""
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
jsc_application_id     = ""
jsc_application_secret = ""

## tryjamf Okta Account Details
tje_okta_client_id  = ""
tje_okta_org_domain = ""

##################################
##### ONBOARDER MODULE KNOBS #####
##################################

## (Jamf Pro) General Settings Knobs ##
include_categories                   = false

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
