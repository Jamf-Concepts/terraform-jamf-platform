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

resource "jamfpro_category" "apollo_11" {
  name     = "Apollo 11"
  priority = 9
}

resource "jamfpro_category" "apollo_12" {
  name     = "Apollo 12"
  priority = 9
}

resource "jamfpro_category" "apollo_13" {
  name     = "Apollo 13"
  priority = 9
}

resource "jamfpro_category" "apollo_14" {
  name     = "Apollo 14"
  priority = 9
}

resource "jamfpro_category" "apollo_15" {
  name     = "Apollo 15"
  priority = 9
}

resource "jamfpro_category" "apollo_16" {
  name     = "Apollo 16"
  priority = 9
}

resource "jamfpro_category" "apollo_17" {
  name     = "Apollo 17"
  priority = 9
}
