## Call Terraform provider
terraform {
  required_providers {
    jsc = {
      source                = "danjamf/jsctfprovider"
      configuration_aliases = [jsc.jsc]
    }
  }
}

resource "jsc_blockpage" "data_block" {
  title               = "Content Blocked"
  description         = "Your Text Here"
  type                = "block"
  show_requesturl     = true
  show_classification = true

}

resource "jsc_blockpage" "secure_block" {
  title               = "Security Risk"
  description         = "Your Text Here"
  type                = "secureBlock"
  show_requesturl     = false
  show_classification = true
  depends_on          = [jsc_blockpage.data_block]
}

resource "jsc_blockpage" "cap" {
  title               = "Data Limit Reached"
  description         = "Your Text Here"
  type                = "cap"
  show_requesturl     = true
  show_classification = true
  depends_on          = [jsc_blockpage.secure_block]
}

resource "jsc_blockpage" "device_risk" {
  title               = "Access Blocked Due to Device Risk"
  description         = "Your Text Here"
  type                = "deviceRisk"
  show_requesturl     = true
  show_classification = true
  depends_on          = [jsc_blockpage.cap]
}

resource "jsc_blockpage" "mangement_block" {
  title               = "Un-Managed Device - Access Restricted"
  description         = "Your Text Here"
  type                = "deviceManagement"
  show_requesturl     = true
  show_classification = true
  depends_on          = [jsc_blockpage.device_risk]
}

