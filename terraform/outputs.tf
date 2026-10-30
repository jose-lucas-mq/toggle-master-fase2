# =============================================================================
# REDE
# =============================================================================
output "vpc_id" {
  description = "ID da VPC dedicada ao ToggleMaster."
  value       = module.networking.vpc_id
}
output "public_subnet_ids" {
  description = "IDs das 3 sub-redes públicas (ALB, Bastion, NAT GWs)."
  value       = module.networking.public_subnet_ids
}
output "private_subnet_ids" {
  description = "IDs das 3 sub-redes privadas (EKS nodes, RDS, Redis)."
  value       = module.networking.private_subnet_ids
}

# =============================================================================
# ECR (5 URLs dos repositórios p/ build & push)
# =============================================================================
output "auth_service_ecr_url" { value = module.ecr.repo_urls["auth-service"] }
output "flag_service_ecr_url" { value = module.ecr.repo_urls["flag-service"] }
output "targeting_service_ecr_url" { value = module.ecr.repo_urls["targeting-service"] }
output "evaluation_service_ecr_url" { value = module.ecr.repo_urls["evaluation-service"] }
output "analytics_service_ecr_url" { value = module.ecr.repo_urls["analytics-service"] }

# =============================================================================
# 3 X RDS POSTGRESQL
# =============================================================================
output "auth_rds_endpoint" {
  value       = module.rds_auth.endpoint
  description = "Endpoint (host:port) do RDS auth-service."
  sensitive   = false
}
output "auth_rds_username" { value = module.rds_auth.username }
output "auth_rds_password" {
  value       = module.rds_auth.password
  description = "Senha master do RDS auth. Mantenha em segredo; use SSM Parameter Store ou Secrets Manager."
  sensitive   = true
}

output "flags_rds_endpoint" { value = module.rds_flags.endpoint }
output "flags_rds_username" { value = module.rds_flags.username }
output "flags_rds_password" {
  value       = module.rds_flags.password
  description = "Senha master flags RDS."
  sensitive   = true
}

output "targeting_rds_endpoint" { value = module.rds_targeting.endpoint }
output "targeting_rds_username" { value = module.rds_targeting.username }
output "targeting_rds_password" {
  value       = module.rds_targeting.password
  description = "Senha master targeting RDS."
  sensitive   = true
}

# =============================================================================
# SECURITY GROUP IDs (preciso para permitir tráfego Nós EKS → RDS/Redis)
# =============================================================================
output "sg_rds_auth_id" { value = module.rds_auth.security_group_id }
output "sg_rds_flags_id" { value = module.rds_flags.security_group_id }
output "sg_rds_targeting_id" { value = module.rds_targeting.security_group_id }
output "sg_redis_id" { value = module.elasticache_redis.security_group_id }

# =============================================================================
# REDIS ELASTICACHE
# =============================================================================
output "redis_endpoint_address" {
  description = "Endpoint primário do Redis ElastiCache (sem porta)."
  value       = module.elasticache_redis.primary_endpoint_address
}
output "redis_port" { value = module.elasticache_redis.port }

# =============================================================================
# SQS
# =============================================================================
output "sqs_events_url" {
  description = "URL da fila SQS toggle-master-events (evaluation envia, analytics consome)."
  value       = module.sqs_events.queue_url
}
output "sqs_events_arn" {
  description = "ARN da fila principal (para políticas IAM least-privilege)."
  value       = module.sqs_events.queue_arn
}
output "sqs_dlq_url" {
  value       = module.sqs_events.dlq_url
  description = "URL DLQ (se enabled, vazia se disabled)."
}
output "sqs_dlq_arn" {
  value       = module.sqs_events.dlq_arn
  description = "ARN DLQ."
}

# =============================================================================
# DYNAMODB ANALYTICS
# =============================================================================
output "dynamodb_analytics_table_name" {
  description = "Nome da tabela (ToggleMasterAnalytics) - variável AWS_DYNAMODB_TABLE dos apps."
  value       = module.dynamodb_analytics.table_name
}
output "dynamodb_analytics_table_arn" {
  description = "ARN p/ políticas IAM least-privilege analytics PutItem."
  value       = module.dynamodb_analytics.table_arn
}

# =============================================================================
# EKS CLUSTER (Sprint 2)
# =============================================================================
output "eks_cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.eks_cluster.cluster_name
}
output "eks_cluster_endpoint" {
  description = "Endpoint público da API do Kubernetes (kubectl)."
  value       = module.eks_cluster.cluster_endpoint
}
output "eks_cluster_version" {
  description = "Versão do Kubernetes no cluster."
  value       = module.eks_cluster.cluster_version
}
output "eks_cluster_security_group_id" {
  description = "ID do Security Group do Control Plane EKS."
  value       = module.eks_cluster.cluster_security_group_id
}
output "eks_node_security_group_id" {
  description = "ID do Security Group dos nós workers (use para permitir tráfego RDS/Redis a partir do EKS)."
  value       = module.eks_cluster.node_security_group_id
}
output "eks_node_role_arn" {
  description = "ARN da role IAM dos nós workers."
  value       = module.eks_cluster.node_role_arn
}
output "eks_oidc_provider_arn" {
  description = "ARN do OIDC Provider do cluster (base para IRSA)."
  value       = module.eks_cluster.oidc_provider_arn
}
output "eks_oidc_issuer_url" {
  description = "URL do issuer OIDC do cluster."
  value       = module.eks_cluster.oidc_issuer_url
}
output "eks_kubeconfig_command" {
  description = "Comando para configurar kubectl local."
  value       = module.eks_cluster.kubeconfig_command
}

# =============================================================================
# IRSA Roles (Sprint 2)
# =============================================================================
output "irsa_evaluation_role_arn" {
  description = "ARN da role IRSA do pod evaluation-service (anotar no ServiceAccount apps/evaluation-sa)."
  value       = module.iam_irsa.evaluation_pod_role_arn
}
output "irsa_analytics_role_arn" {
  description = "ARN da role IRSA do pod analytics-service (anotar no ServiceAccount apps/analytics-sa)."
  value       = module.iam_irsa.analytics_pod_role_arn
}
output "irsa_keda_role_arn" {
  description = "ARN da role IRSA do KEDA Operator (anotar no ServiceAccount keda/keda-operator)."
  value       = module.iam_irsa.keda_operator_role_arn
}
output "all_irsa_role_arns" {
  description = "Map com todas as roles IRSA (evaluation/analytics/keda)."
  value       = module.iam_irsa.all_irsa_role_arns
}
