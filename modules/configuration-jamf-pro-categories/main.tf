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

resource "random_integer" "entropy" {
  min = 10
  max = 999
}

## Create Categories

resource "jamfpro_category" "category_communication" {
  name     = "Communication [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_category" "category_developer_tools" {
  name     = "Developer Tools [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_category" "category_network" {
  name     = "Network Security [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_category" "category_printers" {
  name     = "Printers [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_category" "category_productivity" {
  name     = "Productivity [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_category" "category_security_compliance" {
  name     = "Security and Compliance [${random_integer.entropy.result}]"
  priority = 9
}

resource "jamfpro_category" "category_uninstallers" {
  name     = "Uninstallers [${random_integer.entropy.result}]"
  priority = 9
}
