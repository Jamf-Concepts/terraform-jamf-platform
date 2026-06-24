resource "jamfplatform_pro_local_admin_password_settings" "this" {
  laps_for_prestage_accounts_enabled = false
  rotation_interval                  = 3600
  rotation_after_viewing_interval    = 7776000
}
