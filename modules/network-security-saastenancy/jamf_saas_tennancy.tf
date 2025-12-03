# data "aws_ami" "amazon_linux2_arm64" {
#   most_recent = true
#   owners      = ["amazon"]
#
#   filter {
#     name   = "name"
#     values = ["al2023-ami-2023*-arm64"]
#   }
#   filter {
#     name   = "architecture"
#     values = ["arm64"]
#   }
# }
#
# # Security Group allowing SSH in
# resource "aws_security_group" "instance_sg" {
#   name        = "t4g-micro-sg"
#   description = "Allow SSH, HTTP, and HTTPS inbound"
#
#   # SSH
#   ingress {
#     description      = "SSH"
#     from_port        = 22
#     to_port          = 22
#     protocol         = "tcp"
#     cidr_blocks      = ["116.255.43.177/32"]
#   }
#
#   # HTTP
#   ingress {
#     description      = "HTTP"
#     from_port        = 80
#     to_port          = 80
#     protocol         = "tcp"
#     cidr_blocks      = ["0.0.0.0/0"]
#     ipv6_cidr_blocks = ["::/0"]
#   }
#
#   # HTTPS
#   ingress {
#     description      = "HTTPS"
#     from_port        = 443
#     to_port          = 443
#     protocol         = "tcp"
#     cidr_blocks      = ["0.0.0.0/0"]
#     ipv6_cidr_blocks = ["::/0"]
#   }
#
#   egress {
#     description = "All outbound"
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
#
#   tags = {
#     Name = "t4g-micro-sg"
#   }
# }
#
# # render the user-data script, injecting our URLs
# locals {
#   rendered_userdata = templatefile("${path.module}/init.sh.tpl", {
#     saas_application = var.saas_application
#     allowed_domains = var.allowed_domains
#
#   })
# }
#
# # EC2 instance
# resource "aws_instance" "app" {
#   ami                    = data.aws_ami.amazon_linux2_arm64.id
#   instance_type          = "t4g.micro"
#   vpc_security_group_ids = [aws_security_group.instance_sg.id]
#   associate_public_ip_address = false  # we’ll attach an EIP instead
#   key_name = var.ssh_key_name
#
#   # Render the init.sh.tpl with Terraform vars, then Base64-encode it
#   user_data = local.rendered_userdata
#
#   tags = {
#     Name = "SaaS Tenancy"
#   }
# }
#
# # Elastic IP + association
# resource "aws_eip" "instance_eip" {
#   instance = aws_instance.app.id
#   vpc      = true
#
#   tags = {
#     Name = "t4g-micro-eip"
#   }
# }
