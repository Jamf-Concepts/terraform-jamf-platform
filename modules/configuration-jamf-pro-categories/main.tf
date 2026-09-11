## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "jamf/jamfplatform"
      version               = ">= 0.32.0"
      configuration_aliases = [jamfplatform.jpro]
    }
  }
}

## Categories not specific to an "outcome". If relative to an outcome the category is created in the specific outcome module

## Create Categories

resource "jamfplatform_pro_category" "category_communication" {
  name     = "[Foundations] Communication"
  priority = 9
}

resource "jamfplatform_pro_category" "category_developer_tools" {
  name     = "[Foundations] Developer Tools"
  priority = 9
}

resource "jamfplatform_pro_category" "category_network" {
  name     = "[Foundations] Network Security"
  priority = 9
}

resource "jamfplatform_pro_category" "category_printers" {
  name     = "[Foundations] Printers"
  priority = 9
}

resource "jamfplatform_pro_category" "category_productivity" {
  name     = "[Foundations] Productivity"
  priority = 9
}

resource "jamfplatform_pro_category" "category_security_compliance" {
  name     = "[Foundations] Security and Compliance"
  priority = 9
}

resource "jamfplatform_pro_category" "category_uninstallers" {
  name     = "[Foundations] Uninstallers"
  priority = 9
}
