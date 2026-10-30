variable "name_prefix" { type = string }
variable "visibility_timeout_seconds" { type = number }
variable "message_retention_seconds" { type = number }
variable "long_polling_wait_seconds" { type = number }
variable "create_dlq" { type = bool }
variable "dlq_max_receive_count" { type = number }
variable "tags" { type = map(string) }
