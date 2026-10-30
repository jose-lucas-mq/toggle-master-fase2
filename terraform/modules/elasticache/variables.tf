variable "name_prefix" { type = string }
variable "node_type" { type = string }
variable "engine_version" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "tags" { type = map(string) }

variable "engine" {
  type    = string
  default = "redis"
}
variable "port" {
  type    = number
  default = 6379
}
variable "automatic_failover_enabled" {
  type    = bool
  default = false
}
variable "num_cache_nodes" {
  type    = number
  default = 1
}
variable "parameter_group_family" {
  type    = string
  default = "redis7"
}
variable "apply_immediately" {
  type    = bool
  default = true
}
