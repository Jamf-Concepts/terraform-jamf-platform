# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Packages.html
#
# Packages are downloaded from the URLs in the map and uploaded to the Jamf Pro
# distribution point on the first apply. To upgrade a package, update the URL —
# Terraform will re-download and re-upload on the next apply. Package names
# are derived from the filename in the URL via basename().

locals {
  package_urls = {
    # Microsoft CDN URLs contain a version-specific UUID path segment and will
    # break when Microsoft releases a new version. Check
    # https://github.com/macadmins/nudge/releases for the latest Nudge URL.
    # When updating the Nudge URL, also update the version values in the
    # nudge_is_installed smart group in smart_computer_groups.tf.
    microsoft_company_portal = "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/CompanyPortal_5.2603.0-Upgrade.pkg"
    nudge                    = "https://github.com/macadmins/nudge/releases/download/v2.1.3.81860/Nudge_Essentials-2.1.3.81860.pkg"
  }
}

resource "jamfpro_package" "default" {
  for_each              = local.package_urls
  package_name          = basename(each.value)
  package_file_source   = each.value
  category_id           = jamfpro_category.common["applications"].id
  info                  = "Managed by Terraform"
  priority              = 10
  reboot_required       = false
  fill_user_template    = false
  os_install            = false
  suppress_updates      = false
  suppress_from_dock    = false
  suppress_eula         = false
  suppress_registration = false
}

