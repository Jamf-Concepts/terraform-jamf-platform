# State backend configuration for the dev environment.
#
# By default this folder uses LOCAL state. Each `terraform apply` writes to
# environments/dev/terraform.tfstate alongside this file. Local state is
# fine for learning and personal sandboxes.
#
# For any environment you don't want to lose, switch to a remote backend.
# Remote state gives you:
#   - State locking (prevents two people applying at once)
#   - Encryption at rest
#   - A single source of truth for the team
#   - Easier disaster recovery
#
# To migrate, comment out the `backend "local"` block below, uncomment ONE
# of the four examples beneath the terraform block, fill in the values for
# your account, then run:
#
#     terraform init -migrate-state
#
# Terraform will detect the change and offer to copy your existing state
# into the new backend.

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# ---------------------------------------------------------------------
# Remote backend examples - uncomment exactly ONE of the blocks below.
# ---------------------------------------------------------------------
#
# HCP Terraform / Terraform Cloud
# Recommended starting point for teams. Free tier covers up to 500
# resources. Create one workspace per environment in the same organisation.
#
# terraform {
#   cloud {
#     organization = "your-org"
#     workspaces {
#       name = "jamf-dev"
#     }
#   }
# }
#
# ---------------------------------------------------------------------
#
# AWS S3
# The bucket should have versioning enabled. Terraform 1.10+ supports
# native S3 locking via use_lockfile = true — no DynamoDB table needed.
#
# terraform {
#   backend "s3" {
#     bucket       = "your-tfstate-bucket"
#     key          = "jamf/dev/terraform.tfstate"
#     region       = "eu-west-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
#
# ---------------------------------------------------------------------
#
# Google Cloud Storage
# GCS provides locking via object generation numbers, so no separate
# lock table is needed. The bucket should have versioning enabled.
#
# terraform {
#   backend "gcs" {
#     bucket = "your-tfstate-bucket"
#     prefix = "jamf/dev"
#   }
# }
#
# ---------------------------------------------------------------------
#
# Azure Storage
# Storage account and container must already exist. Locking is provided
# by Azure Blob lease.
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "your-rg"
#     storage_account_name = "yourtfstate"
#     container_name       = "tfstate"
#     key                  = "jamf/dev/terraform.tfstate"
#   }
# }
