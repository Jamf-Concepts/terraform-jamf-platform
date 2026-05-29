# This module declares which providers it needs. Provider configuration
# (URLs, credentials) is the responsibility of the root module that calls
# this one - typically environments/<env>/provider.tf.
#
# Terraform will pass configured providers from the root into this module
# implicitly, so no explicit `providers = { ... }` block is required at the
# call site unless you're using provider aliases.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.37.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.13.0"
    }
    itunessearchapi = {
      source  = "neilmartin83/itunessearchapi"
      version = ">= 0.1.0"
    }
  }
}
