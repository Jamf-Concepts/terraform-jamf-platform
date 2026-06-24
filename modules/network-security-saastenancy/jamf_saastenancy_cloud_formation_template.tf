

data "aws_vpc" "default" {
  default = true
}




# Define local mappings for AMI IDs based on region
locals {
  region_amis = {
    "us-east-1"      = "ami-0eb01a520e67f7f20"
    "us-east-2"      = "ami-07a5db12eede6ff87"
    "us-west-1"      = "ami-05f45e0f5aeac9a24"
    "us-west-2"      = "ami-00a0b62a1660255c0"
    "ap-southeast-2" = "ami-01b5f7a30f320f409"
    "ap-northeast-1" = "ami-09ff6f432d0ee628e"
    "eu-central-1"   = "ami-00068b9d3a9643636"
    "eu-west-2"      = "ami-05e77069ed898709c"
  }

  init_script = templatefile("${path.module}/script.sh", {
    SaaSApplication       = var.SaaSApplication
    Domain                = var.Domain
    CertificateBody       = var.CertificateBody
    CertificatePrivateKey = var.CertificatePrivateKey
  })

  domain_array = split(" ", var.Domain)
}



# Resources
resource "aws_security_group" "InstanceSecurityGroup" {
  name        = "InstanceSecurityGroup"
  description = "Allow access to port 443 and 80"
  # Use the VPC ID from the variable if it's provided, otherwise fall back to the default VPC
  vpc_id = var.VPCId != "" ? var.VPCId : data.aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional: Define egress rules (default allows all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "InstanceSecurityGroup"
  }
}

resource "aws_instance" "SaaSTenancyNginx" {
  instance_type          = var.InstanceType
  vpc_security_group_ids = [aws_security_group.InstanceSecurityGroup.id]
  key_name               = var.KeyName
  ami                    = local.region_amis[var.aws_region]
  subnet_id              = var.SubnetId
  user_data_base64       = base64gzip(local.init_script)


  tags = {
    Name = "SaaSTenancyNginx"
  }

  # Add any other required configurations here.
}

resource "aws_eip" "ElasticIP" {
  domain   = "vpc"
  instance = aws_instance.SaaSTenancyNginx.id
}

# Outputs
output "InstanceId" {
  description = "The Instance ID"
  value       = aws_instance.SaaSTenancyNginx.id
}

output "PublicIP" {
  description = "The Public IP address of the instance please add this as your JSC custom gateway address"
  value       = aws_eip.ElasticIP.public_ip
}

output "userdata" {
  value     = local.init_script
  sensitive = true
}
