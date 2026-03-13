locals {
  remote_remedy = templatefile("${path.module}/support_files/remote_remedy.tpl", {
    extension_attribute_id = jamfpro_computer_extension_attribute.remote_remedy_session.id
  })
}
