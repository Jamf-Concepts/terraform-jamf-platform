variable "KeyName" {
  type        = string
  sensitive   = false
  default     = ""
  description = "AWS Keyname to attach to SaaS Tenancy instance. If blank, no SSH access will be possible"
}

variable "VPCId" {
  type        = string
  sensitive   = false
  default     = ""
  description = "AWS VPC to attach SaaS Tenancy Instance to."
}

variable "SubnetId" {
  type        = string
  sensitive   = false
  default     = ""
  description = "AWS SubnetID to attach SaaS Tenancy Instance to."
}

variable "CertificateBody" {
  type        = string
  sensitive   = false
  default     = ""
  description = "Provided Cert Body for TLS inspection. If not provided, self-signed will be generated"
}

variable "CertificatePrivateKey" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Provided Cert PrivateKey for TLS inspection. If not provided, self-signed will be generated"
}

variable "aws_region" {
  type        = string
  sensitive   = false
  default     = "us-west-2"
  description = "AWS region for SaaS tenancy instance"
}

variable "jsc_username" {
  description = "JSC username (email)"
  type        = string
}

variable "jsc_password" {
  description = "JSC password"
  type        = string
  sensitive   = true
}


variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "Domain" {
  description = "internal domain to add to the header if multiple seperated by space"
  type        = string
  default     = "accounts.google.com"
}
variable "SaaSApplication" {
  description = "Choose which application to allow for the domain"
  type        = string
  default     = "Google"
}
variable "InstanceType" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.micro"
}

variable "jamfpro_client_id" {
  type      = string
  sensitive = true
}

variable "jamfpro_client_secret" {
  type      = string
  sensitive = true
}

variable "jamfpro_instance_url" {
  type      = string
  sensitive = true
}

variable "random_string" {
  type    = string
  default = ""
}

