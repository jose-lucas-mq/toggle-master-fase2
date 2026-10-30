variable "name_prefix" { type = string }
variable "billing_mode" { type = string }
variable "create_gsis" { type = bool }
variable "ttl_enabled" { type = bool }
variable "tags" { type = map(string) }

variable "table_name" {
  type        = string
  default     = "ToggleMasterAnalytics"
  description = "Nome da tabela de analytics fixo (matches código apps)."
}
variable "ttl_attribute_name" {
  type        = string
  default     = "ttl_epoch"
  description = "Nome do atributo TTL numérico (epoch seconds). App precisa gravar este campo."
}
variable "provisioned_read_capacity" {
  type    = number
  default = 5
}
variable "provisioned_write_capacity" {
  type    = number
  default = 5
}
