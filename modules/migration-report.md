# jamformer migrate — 2026-06-24

Input: `/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/`

| Result | Count |
|--------|-------|
| ✓ Migrated cleanly | 228 |
| ⚠ Manual review | 10 |
| ✗ Skipped | 0 |

## Manual review required

⚠  jamfplatform_pro_sso_settings.adminsso  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/configuration-jamf-pro-admin-sso/main.tf)
   Reason: SSO settings restructured — security-sensitive, verify all sub-attributes
   Action: review sso_settings carefully; SAML and OIDC sub-attrs may differ

⚠  jamfplatform_pro_app_installer.jamfpro_app_installer_microsoft_defender  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/endpoint-security-macOS-microsoft-defender/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.app_installers  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-app-installers/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.google_chrome  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-app-installers-google-chrome-cloud-management/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.jamfpro_app_installer_microsoft_excel  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-macOS-microsoft-365/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.jamfpro_app_installer_microsoft_powerpoint_365  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-macOS-microsoft-365/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.jamfpro_app_installer_microsoft_outlook_365  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-macOS-microsoft-365/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.jamfpro_app_installer_microsoft_onedrive_365  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-macOS-microsoft-365/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.jamfpro_app_installer_microsoft_word_365  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-macOS-microsoft-365/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

⚠  jamfplatform_pro_app_installer.jamfpro_app_installer_microsoft_teams_365  (/Users/admin/Documents/GitHub/jamf/terraform-jamf-platform/modules/management-macOS-microsoft-365/main.tf)
   Reason: app_title_name added (same value as name) — verify catalog title matches exactly
   Action: verify app_title_name matches the exact title in the Jamf App Catalog

