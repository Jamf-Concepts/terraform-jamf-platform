## Call Terraform provider
terraform {
  required_providers {
    jamfplatform = {
      source                = "Jamf-Concepts/jamfplatform"
      version               = ">= 0.29.0"
      configuration_aliases = [jamfplatform.jpro]
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

## jsc_ap (Jamf-Concepts/jsctfprovider) is replaced by the native
## jamfplatform_security_cloud_activation_profile resource below -- no more
## hand-built plist payloads or a manual "remove the placeholder serial number
## criteria" cleanup step. The deploy action creates and scopes the Jamf Pro
## configuration profile itself; this module no longer creates one directly.

resource "jamfplatform_pro_category" "jsc_all_services_profiles" {
  name     = "Jamf Security Cloud - Activation Profiles"
  priority = 9
}

resource "jamfplatform_device_group" "all_macs" {
  name        = "All Computers"
  group_type  = "smart"
  device_type = "computer"
  criteria = [
    {
      criteria = "Computer Group"
      operator = "member of"
      value    = "All Managed Clients"
    },
  ]
}

resource "jamfplatform_device_group" "supervised_devices" {
  name        = "Supervised Mobile Devices"
  group_type  = "smart"
  device_type = "mobile"
  criteria = [
    {
      criteria = "Supervised"
      operator = "is"
      value    = "Supervised"
    },
  ]
}

resource "jamfplatform_security_cloud_activation_profile" "all_services" {
  name      = "Network Threat and Content Control"
  platforms = ["ios", "mac"]

  capabilities = {
    content_controls = true
    network_security = true
  }
}

## Deploy the activation profile's macOS and supervised-iOS configuration
## profiles to Jamf Pro. The provider only exposes this as
## jamfplatform_security_cloud_activation_profile_deploy, a Terraform "action"
## block (Terraform 1.14+, HashiCorp-only) -- every onboarder in this repo
## runs on OpenTofu (see providers.tf's `>= 1.14` comment and this repo's
## history), whose parser rejects `action`/`action_trigger` syntax outright.
## This calls the same REST operation the action wraps directly instead:
## POST .../uem-connect/v1/activation-profiles/{code}/deploy-to-uem (platform-api
## "JSC UEM Connect API" spec). That operation is documented idempotent, so a
## re-apply is safe. Auth is X-Environment-Id with the plain Platform API
## environment_id -- the OpenAPI spec names the header X-Tenant-Id and implies
## a separate Jamf Security Cloud tenant id, but wire-verified against
## letstest.jamfcloud.com 2026-09-07: X-Tenant-Id with either the environment_id
## or the CSA tenant id (GET /pro/v1/csa/tenant-id) both fail (OWNERSHIP_FORBIDDEN
## / BAD_PERMISSIONS); X-Environment-Id with the environment_id succeeds, and
## matches every other securitycloud/pro call this module already makes.
## uem_connect_dependency only exists to order this resource
## after the sibling UEM Connect module's connector.
resource "null_resource" "deploy_activation_profile" {
  triggers = {
    uem_connect_dependency  = var.uem_connect_dependency
    activation_profile_code = jamfplatform_security_cloud_activation_profile.all_services.id
    mac_group_id            = jamfplatform_device_group.all_macs.jamf_pro_id
    ios_group_id            = jamfplatform_device_group.supervised_devices.jamf_pro_id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      JAMFPLATFORM_BASE_URL       = var.jamfplatform_base_url
      JAMFPLATFORM_CLIENT_ID      = var.jamfplatform_client_id
      JAMFPLATFORM_CLIENT_SECRET  = var.jamfplatform_client_secret
      JAMFPLATFORM_ENVIRONMENT_ID = var.jamfplatform_environment_id
      ACTIVATION_PROFILE_CODE     = jamfplatform_security_cloud_activation_profile.all_services.id
      MAC_GROUP_ID                = jamfplatform_device_group.all_macs.jamf_pro_id
      IOS_GROUP_ID                = jamfplatform_device_group.supervised_devices.jamf_pro_id
    }
    command = <<-EOT
      set -euo pipefail

      case "$JAMFPLATFORM_BASE_URL" in
        us|eu|apac) BASE_URL="https://$JAMFPLATFORM_BASE_URL.api.jamfcloud.com" ;;
        *)          BASE_URL="$JAMFPLATFORM_BASE_URL" ;;
      esac

      TOKEN=$(curl -sf -X POST "$BASE_URL/auth/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials&client_id=$JAMFPLATFORM_CLIENT_ID&client_secret=$JAMFPLATFORM_CLIENT_SECRET" \
        | jq -r '.access_token')

      deploy() {
        platform="$1"
        group="$2"
        body_file=$(mktemp)
        status=$(curl -s -o "$body_file" -w '%%{http_code}' -X POST \
          "$BASE_URL/securitycloud/uem-connect/v1/activation-profiles/$ACTIVATION_PROFILE_CODE/deploy-to-uem" \
          -H "Authorization: Bearer $TOKEN" \
          -H "X-Environment-Id: $JAMFPLATFORM_ENVIRONMENT_ID" \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg platform "$platform" --arg group "$group" '{uem: "JAMF", platform: $platform, uemGroups: [$group]}')")
        if [ "$status" != "204" ]; then
          echo "Activation profile deploy failed for platform=$platform (HTTP $status):" >&2
          cat "$body_file" >&2
          rm -f "$body_file"
          exit 1
        fi
        rm -f "$body_file"
      }

      deploy "SUPERVISED_MAC" "$MAC_GROUP_ID"
      deploy "SUPERVISED_IOS" "$IOS_GROUP_ID"
    EOT
  }
}
