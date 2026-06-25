# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Policies.html
#
# Installs Nudge on laptops at check-in. The exclusion scope targets the
# nudge_is_installed smart group so the policy stops running once the correct
# version is present. When upgrading Nudge, update the package URL in
# packages.tf and the smart group criteria in smart_computer_groups.tf together.

resource "jamfplatform_pro_policy" "install_nudge" {
  general = {
    name            = "Install Nudge (Managed by Terraform)"
    enabled         = true
    trigger_checkin = true
    frequency       = "Ongoing"
    category_id     = jamfplatform_pro_category.common["applications"].id
  }

  scope = {
    targets = {
      computer_group_ids = [
        jamfplatform_device_group.computers_model["laptops"].jamf_pro_id
      ]
    }

    exclusions = {
      computer_group_ids = [
        jamfplatform_device_group.computers_nudge_is_installed.jamf_pro_id
      ]
    }
  }

  packages = {
    distribution_point = "default"
    packages = [
      { id     = jamfplatform_pro_package.default["nudge"].id
        action = "Install"
      },
    ]
  }

  maintenance = {
    update_inventory = true
  }
}
