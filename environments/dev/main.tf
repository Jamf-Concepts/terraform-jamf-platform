# Root module for the dev environment.
#
# This file is intentionally thin. The bulk of the configuration -
# settings, smart groups, profiles, policies, prestages, blueprints, and
# so on - lives in modules/jamfpro/. This root composes the providers
# (see provider.tf), declares its own input variables (see variables.tf),
# reads any environment-specific token files into memory, and calls the
# shared module with this environment's specific values.
#
# Anything that should diverge between environments (a sandbox-only test
# policy, an env-specific smart group, a different scope on a shared
# resource) can be defined here in environments/dev/ alongside the
# module call, OR plumbed through as a module variable.

module "jamfpro" {
  source = "../../modules/jamfpro"

  # Apple-issued token content.
  #
  # Each environment has its own ABM/ASM tenant and therefore its own
  # token files. Token files for THIS environment live in
  # environments/dev/support_files/device_enrollment_tokens/ and
  # environments/dev/support_files/volume_purchasing_tokens/.
  #
  # The path variables below come from terraform.tfvars and are resolved
  # relative to this folder (the working directory Terraform is invoked
  # from). We read each file here, encode appropriately, and pass the
  # resulting *content* to the module. The module never sees the path.
  ade_token_encoded_default = filebase64(var.ade_token_path_default)
  vpp_token_default         = file(var.vpp_token_path_default)

  wifi_ssid     = var.wifi_ssid
  wifi_password = var.wifi_password
}

# --- Environment-specific resources ---
#
# Anything that should exist ONLY in dev and not in other environments
# can be defined directly in this folder. Examples: a smart group used
# for testing, a policy that pushes a beta version of an app to a small
# test scope, an extension attribute used during troubleshooting.
#
# Resources defined here have the same provider config as the module
# (configured in provider.tf) and can reference module outputs as
# `module.jamf.<output_name>` when scoping to module-managed resources.
