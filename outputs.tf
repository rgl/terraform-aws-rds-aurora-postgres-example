output "app_ip_address" {
  value = aws_eip.app.public_ip
}

output "db_admin_username" {
  value = aws_rds_cluster.example.master_username
}

output "db_admin_password" {
  sensitive = true
  value     = aws_rds_cluster.example.master_password
}

output "db_address" {
  value       = aws_rds_cluster.example.endpoint
  description = "NB this is here just for reference. you can only access this address inside the vpc network."
}
