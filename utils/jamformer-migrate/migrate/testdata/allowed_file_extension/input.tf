resource "jamfpro_allowed_file_extension" "thing1" {
  extension = ".thing1"
}

resource "jamfpro_allowed_file_extension" "jpg" {
  extension = ".jpg"
}

resource "jamfpro_allowed_file_extension" "nodot" {
  extension = "pdf"
}
