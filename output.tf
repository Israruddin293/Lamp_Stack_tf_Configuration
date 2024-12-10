output "load_balancer_dns" {
  value = aws_lb.app.dns_name
}

output "rds_endpoint" {
  value = aws_db_instance.mysql.endpoint
}
