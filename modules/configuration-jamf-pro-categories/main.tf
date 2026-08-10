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

## Categories not specific to an "outcome". If relative to an outcome the category is created in the specific outcome module

## Create Categories

resource "jamfplatform_pro_category" "category_communication" {
  name     = "Communication"
  priority = 9
}

resource "jamfplatform_pro_category" "category_developer_tools" {
  name     = "Developer Tools"
  priority = 9
}

resource "jamfplatform_pro_category" "category_network" {
  name     = "Network Security"
  priority = 9
}

resource "jamfplatform_pro_category" "category_printers" {
  name     = "Printers"
  priority = 9
}

resource "jamfplatform_pro_category" "category_productivity" {
  name     = "Productivity"
  priority = 9
}

resource "jamfplatform_pro_category" "category_security_compliance" {
  name     = "Security and Compliance"
  priority = 9
}

resource "jamfplatform_pro_category" "category_uninstallers" {
  name     = "Uninstallers"
  priority = 9
}
