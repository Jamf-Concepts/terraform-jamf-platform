output "instance_id" {
  value = aws_instance.app.id
}

output "public_ip" {
  value = aws_eip.instance_eip.public_ip
}