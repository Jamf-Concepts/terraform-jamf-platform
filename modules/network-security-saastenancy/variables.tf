variable "application_name" {
  description = "Value to tag the attributes within AWS"
  type = string
  default = "Jamf SaaS Tenancy"
}

variable "region" {
  type    = string
  default = ""
}

variable "ec2_type" {
  type    = string
  default = "t4g.micro"
}


variable "aws_profile" {
  type    = string
  default = ""
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 Key Pair in AWS, or one you’ll create below"
  type        = string
  default = ""
}

variable "allowed_domains" {
  description = "A list of the domains to be allowed access"
  type        = list(string)
  default     = [
    "jamf.com",
    "jamfse.io",
  ]
}

variable "saas_application" {
  description = "SaaS Application: Options are Google, Microsoft, Slack, Dropbox"
  type        = string
  default     = "Google"
}

variable "certificate_file" {
  description = "Path to SSL certificate to be used for resigning if left blank one will be generated"
  type        = string
  default     = ""
}

variable "private_key_file" {
  description = "Path to SSL private key to be used for resigning if left blank one will be generated"
  type        = string
  default     = ""
}
