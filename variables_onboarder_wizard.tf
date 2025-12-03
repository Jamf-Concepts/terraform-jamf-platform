variable "install_chrome" {
  type    = bool
  default = false
}

variable "install_firefox" {
  type    = bool
  default = false
}

variable "block_beta_updates" {
  type    = bool
  default = false
}

variable "enforce_firewall_and_gatekeeper" {
  type    = bool
  default = false
}
