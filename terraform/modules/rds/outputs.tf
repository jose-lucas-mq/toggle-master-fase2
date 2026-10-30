output "endpoint" { value = aws_db_instance.this.address }
output "port" { value = aws_db_instance.this.port }
output "hostname" { value = aws_db_instance.this.address }
output "username" { value = aws_db_instance.this.username }
output "password" {
  value     = aws_db_instance.this.password
  sensitive = true
}
output "db_name" { value = aws_db_instance.this.db_name }
output "instance_id" { value = aws_db_instance.this.id }
output "arn" { value = aws_db_instance.this.arn }
output "security_group_id" { value = aws_security_group.rds.id }
output "subnet_group_name" { value = aws_db_subnet_group.this.name }
