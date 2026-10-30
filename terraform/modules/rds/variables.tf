variable "name_prefix" { type = string }
variable "engine_version" { type = string }
variable "instance_class" { type = string }
variable "allocated_storage_gb" { type = number }
variable "max_allocated_storage" { type = number }
variable "multi_az" { type = bool }
variable "backup_retention_days" { type = number }
variable "db_name" { type = string }
variable "db_username" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "tags" { type = map(string) }

variable "storage_type" {
  type    = string
  default = "gp3"
}
variable "engine" {
  type    = string
  default = "postgres"
}
variable "port" {
  type    = number
  default = 5432
}
variable "skip_final_snapshot" {
  type    = bool
  default = true
}
variable "enabled_cloudwatch_logs_exports" {
  type    = list(string)
  default = ["postgresql", "upgrade"]
}
