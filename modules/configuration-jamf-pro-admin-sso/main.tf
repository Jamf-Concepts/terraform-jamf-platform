## Call Terraform provider
terraform {
  required_providers {
    jamfpro = {
      source  = "deploymenttheory/jamfpro"
      version = ">= 0.1.5"
    }
  }
}

# Define a resource to use the local-exec provisioner
resource "null_resource" "run_script" {

  triggers = {
    jamfpro_instance_url  = var.jamfpro_instance_url
    jamfpro_client_id     = var.jamfpro_client_id
    jamfpro_client_secret = var.jamfpro_client_secret
  }
  provisioner "local-exec" {
    command = "${path.module}/adminssoconfigure.sh ${var.jamfpro_instance_url} ${var.jamfpro_client_id} ${var.jamfpro_client_secret}"
    when    = create
  }

  provisioner "local-exec" {
    command = "${path.module}/adminssodelete.sh ${self.triggers.jamfpro_instance_url} ${self.triggers.jamfpro_client_id} ${self.triggers.jamfpro_client_secret}"
    when    = destroy
  }
}
