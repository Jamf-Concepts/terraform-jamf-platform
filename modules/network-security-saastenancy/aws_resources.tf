// aws_resources.tf
// -------------
//
// Data source for the latest Amazon Linux 2023 ARM64 AMI
data "aws_ami" "amazon_linux_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}


//
// Security Group: allow SSH, HTTP, HTTPS
resource "aws_security_group" "instance_sg" {
  name        = var.application_name
  description = "Allow SSH (22), HTTP (80) and HTTPS (443)"

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["116.255.43.177/32"]
  }
  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.application_name}-security_group"
  }
}

//
// EC2 instance, with templated user-data rendered in locals.tf
resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux_arm64.id
  instance_type               = var.ec2_type
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  associate_public_ip_address = false
  key_name                    = var.ssh_key_name

  # rendered_userdata is defined in locals.tf
  user_data_base64 = base64encode(local.rendered_userdata)

  tags = {
    Name = var.application_name
  }
}

//
// Elastic IP for the instance
resource "aws_eip" "instance_eip" {
  vpc      = true
  instance = aws_instance.app.id

  tags = {
    Name = "${var.application_name}-eip"
  }
}