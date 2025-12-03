variable "block_page_logo" {
  type      = string
  sensitive = false
  default   = ""
}

variable "jsc_username" {
  type      = string
  sensitive = false
  default   = ""
}

variable "jsc_password" {
  type      = string
  sensitive = true
  default   = ""
}
