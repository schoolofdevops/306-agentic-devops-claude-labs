output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "web_security_group_id" {
  description = "ID of the web tier security group."
  value       = aws_security_group.web.id
}

output "app_security_group_id" {
  description = "ID of the app tier security group."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "ID of the database tier security group."
  value       = aws_security_group.db.id
}
