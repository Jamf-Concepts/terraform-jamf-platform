locals {
  remote_remedy = templatefile("${path.module}/support_files/remote_remedy.tpl", {
    extension_attribute_id = output.remote_remedy_extension_attribute
  })
}
