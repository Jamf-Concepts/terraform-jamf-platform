# https://learn.jamf.com/en-US/bundle/jamf-pro-documentation-current/page/Packages.html
#
# Packages are downloaded from the URLs in the map and uploaded to the Jamf Pro
# distribution point on the first apply. To upgrade a package, update the URL.
# Terraform will re-download and re-upload on the next apply. Package names
# are derived from the filename in the URL via basename(). Set filename when
# the URL is a redirect and basename() would produce a garbage name.

locals {
  packages = {
    # Microsoft's fwlink URL is a redirect, so basename() gives a garbage query string,
    # so filename is set explicitly.
    microsoft_company_portal = {
      url      = "https://go.microsoft.com/fwlink/?linkid=862280"
      filename = "CompanyPortal-Installer.pkg"
    }
    # Check https://github.com/macadmins/nudge/releases for the latest Nudge URL.
    # When updating the Nudge URL, also update the version values in the
    # nudge_is_installed smart group in smart_computer_groups.tf.
    nudge = {
      url      = "https://github.com/macadmins/nudge/releases/download/v2.1.3.81860/Nudge_Essentials-2.1.3.81860.pkg"
      filename = null
    }
  }
}

resource "jamfplatform_pro_package" "default" {
  for_each            = local.packages
  display_name        = coalesce(each.value.filename, basename(each.value.url))
  file_name           = coalesce(each.value.filename, basename(each.value.url))
  package_file_source = each.value.url
  category_id         = jamfplatform_pro_category.common["applications"].id
}
