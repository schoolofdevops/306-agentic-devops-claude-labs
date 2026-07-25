output "endpoint" {
  description = "Connection endpoint of the database instance."
  value       = aws_db_instance.main.endpoint
}

output "port" {
  description = "Port the database instance listens on."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the initial database created on the instance."
  value       = aws_db_instance.main.db_name
}

output "db_instance_id" {
  description = "Identifier of the RDS database instance."
  value       = aws_db_instance.main.id
}
