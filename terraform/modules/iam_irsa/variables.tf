variable "name_prefix" {
  description = "Prefixo para nomes das roles IAM."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC Provider do cluster EKS (output do módulo eks_cluster)."
  type        = string
}

variable "oidc_issuer_url" {
  description = "URL completa do issuer OIDC (ex: https://oidc.eks.us-east-1.amazonaws.com/id/XXXX)."
  type        = string
}

variable "aws_account_id" {
  description = "ID da conta AWS (12 dígitos) - usado para montar ARNs de recursos."
  type        = string
}

variable "aws_region" {
  description = "Região AWS dos recursos (SQS, DynamoDB)."
  type        = string
  default     = "us-east-1"
}

variable "sqs_events_queue_arn" {
  description = "ARN da fila SQS toggle-master-events (output do módulo sqs)."
  type        = string
}

variable "sqs_dlq_arn" {
  description = "ARN da fila DLQ (output do módulo sqs)."
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB ToggleMasterAnalytics."
  type        = string
}

variable "tags" {
  description = "Tags padrão."
  type        = map(string)
  default     = {}
}
