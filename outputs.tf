##############################
# Outputs
##############################

output "rds_endpoint" {
  description = "Endpoint of the RDS PostgreSQL instance"
  value       = aws_db_instance.postgres.address
}

output "connection_string" {
  description = "PostgreSQL connection string for the CDC tool"
  value       = "postgresql://postgres:password@${aws_db_instance.postgres.address}:5432/demo"
}

output "rds_username" {
  description = "Username for the RDS PostgreSQL instance"
  value       = aws_db_instance.postgres.username
}

output "rds_password" {
  description = "Password for the RDS PostgreSQL instance"
  value       = aws_db_instance.postgres.password
  sensitive   = true
}

output "source_schema" {
  description = "The schema where the CDC source table resides"
  value       = "source"
}

output "source_table" {
  description = "The table to monitor for CDC changes"
  value       = "live_data"
}

output "ec2_instance_public_ip" {
  description = "Public IP of the EC2 data generator instance"
  value       = aws_instance.data_generator.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the data generator instance"
  value       = "ssh ec2-user@${aws_instance.data_generator.public_ip}"
}

output "check_command" {
  description = "Command to check data generator status after SSH"
  value       = "./check_generator.sh"
}