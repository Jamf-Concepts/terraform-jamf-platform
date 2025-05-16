## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source                = "deploymenttheory/jamfpro"
      configuration_aliases = [jamfpro.jpro]
    }
  }
}

## Categories not specific to an "outcome". If relative to an outcome the category is created in the specific outcome module

## Create Categories

resource "jamfpro_category" "category_communication" {
  name     = "Communication ${var.entropy_string}"
  priority = 9
}

resource "jamfpro_category" "category_developer_tools" {
  name     = "Developer Tools ${var.entropy_string}"
  priority = 9
}

resource "jamfpro_category" "category_network" {
  name     = "Network Security ${var.entropy_string}"
  priority = 9
}

resource "jamfpro_category" "category_printers" {
  name     = "Printers ${var.entropy_string}"
  priority = 9
}

resource "jamfpro_category" "category_productivity" {
  name     = "Productivity ${var.entropy_string}"
  priority = 9
}

resource "jamfpro_category" "category_security_compliance" {
  name     = "Security and Compliance ${var.entropy_string}"
  priority = 9
}

resource "jamfpro_category" "category_uninstallers" {
  name     = "Uninstallers ${var.entropy_string}"
  priority = 9
}
