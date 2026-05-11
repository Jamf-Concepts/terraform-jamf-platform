# Use this file to import existing Jamf Pro resources into Terraform management.
#
# Find the numeric resource ID via jamf-cli:
#   jamf-cli pro get categories
#   jamf-cli pro get scripts
#
# Uncomment and fill in the blocks below, then run:
#   terraform plan -parallelism=1 -generate-config-out=generated.tf
#
# Review generated.tf, copy the resource block into the appropriate .tf file,
# then delete the import block below and generated.tf before your next plan.

# import {
#   to = jamfpro_category.engineering
#   id = ""  # numeric ID from Jamf Pro
# }

# import {
#   to = jamfpro_script.hello_world
#   id = ""  # numeric ID from Jamf Pro
# }
