resource "jamfpro_disk_encryption_configuration" "individual" {
  name                     = "Individual recovery key"
  key_type                 = "Individual"
  file_vault_enabled_users = "Management Account"
}

resource "jamfpro_disk_encryption_configuration" "institutional" {
  name                     = "Institutional recovery key"
  key_type                 = "Institutional"
  file_vault_enabled_users = "Current or Next User"

  institutional_recovery_key {
    certificate_type = "PKCS12"
    data             = "BASE64_PLACEHOLDER=="
    password         = "change-me"
  }
}
