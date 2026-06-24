resource "jamfplatform_pro_printer" "lab_color" {
  name         = "tf-example-printer-specific_ppd-01"
  uri          = "lpd://10.1.20.204/"
  cups_name    = "HP_DesignJet_1050C_PS3"
  location     = "Building 5, floor 2"
  model        = "HP DesignJet 1050C PS3"
  info         = "string"
  notes        = "string"
  make_default = true
  use_generic  = false
  ppd          = "HP_DesignJet_1050C_PS3.ppd"
  ppd_path     = "/somepath"
  category     = "Printers"
}
