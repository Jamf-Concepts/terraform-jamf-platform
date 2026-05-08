# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Policies.html
#
# Installs Nudge on laptops at check-in. The exclusion scope targets the
# nudge_is_installed smart group so the policy stops running once the correct
# version is present. When upgrading Nudge, update the package URL in
# packages.tf and the smart group criteria in smart_computer_groups.tf together.

resource "jamfpro_policy" "install_nudge" {
  name            = "Install Nudge (Managed by Terraform)"
  enabled         = true
  trigger_checkin = true
  frequency       = "Ongoing"
  category_id     = jamfpro_category.common["applications"].id
  scope {
    all_computers = false
    computer_group_ids = [
      jamfpro_smart_computer_group_v2.model["laptops"].id
    ]
    exclusions {
      computer_group_ids = [jamfpro_smart_computer_group_v2.nudge_is_installed.id]
    }
  }
  payloads {
    packages {
      distribution_point = "default"
      package {
        id     = jamfpro_package.default["nudge"].id
        action = "Install"
      }
    }
    maintenance {
      recon = true
    }
  }
}
