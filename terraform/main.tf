locals {
  name_prefix = "toggle-master"
}

# =============================================================================
# 1) NETWORKING: VPC, Subnets, IGW, NAT, Route Tables, Security Groups base
# =============================================================================
module "networking" {
  source = "./modules/networking"

  aws_region  = var.aws_region
  name_prefix = local.name_prefix

  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = var.common_tags
}

# =============================================================================
# 2) ECR: 5 repositórios privados (1 por microsserviço)
# =============================================================================
module "ecr" {
  source = "./modules/ecr"

  name_prefix = local.name_prefix
  repos = [
    { name = "auth-service" },
    { name = "flag-service" },
    { name = "targeting-service" },
    { name = "evaluation-service" },
    { name = "analytics-service" },
  ]
  tags = var.common_tags
}

# =============================================================================
# 3) RDS: 3 instâncias PostgreSQL independentes + suas Security Groups
#        Inicializa master username/password com random_password.
# =============================================================================
resource "random_password" "rds_master_password" {
  for_each = toset(["auth", "flags", "targeting"])
  length   = 24
  upper    = true
  lower    = true
  numeric  = true
  # IMPORTANTE: AWS RDS PROÍBE caracteres "/", "@", aspas duplas e " " (espaço)
  # em MasterUserPassword. NÃO adicionar esses caracteres no override_special!
  # Também evitamos caracteres que quebram parsers de URL/DSN:
  #   "%"  -> interpretado como percent-encoding (psycopg2: invalid percent-encoded token)
  #   "#"  -> delimitador de fragment em URL
  #   "{}" -> inválidos em userinfo (Go net/url: invalid userinfo)
  #   "[]" -> inválidos em userinfo (Go net/url: invalid userinfo)
  #   "()" -> podem confundir parsers em alguns contextos
  special          = true
  override_special = "!$&*+-_="
}

module "rds_auth" {
  source = "./modules/rds"

  name_prefix           = "${local.name_prefix}-auth"
  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage_gb  = var.rds_storage_gb
  max_allocated_storage = var.rds_storage_max_gb
  multi_az              = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention_days

  # DB layout (bancos criados no primeiro boot do app init.sql)
  db_name     = "auth_db"
  db_username = "auth_user"
  db_password = random_password.rds_master_password["auth"].result

  # Rede e segurança
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  tags               = var.common_tags
}

module "rds_flags" {
  source = "./modules/rds"

  name_prefix           = "${local.name_prefix}-flags"
  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage_gb  = var.rds_storage_gb
  max_allocated_storage = var.rds_storage_max_gb
  multi_az              = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention_days

  db_name     = "flags_db"
  db_username = "flag_user"
  db_password = random_password.rds_master_password["flags"].result

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  tags               = var.common_tags
}

module "rds_targeting" {
  source = "./modules/rds"

  name_prefix           = "${local.name_prefix}-targeting"
  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  allocated_storage_gb  = var.rds_storage_gb
  max_allocated_storage = var.rds_storage_max_gb
  multi_az              = var.rds_multi_az
  backup_retention_days = var.rds_backup_retention_days

  db_name     = "targeting_db"
  db_username = "targeting_user"
  db_password = random_password.rds_master_password["targeting"].result

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  tags               = var.common_tags
}

# =============================================================================
# 4) ELASTICACHE: Redis cluster hot path evaluation-service cache
# =============================================================================
module "elasticache_redis" {
  source = "./modules/elasticache"

  name_prefix    = local.name_prefix
  node_type      = var.redis_node_type
  engine_version = var.redis_engine_version

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  tags               = var.common_tags
}

# =============================================================================
# 5) SQS: Fila standard toggle-master-events + DLQ (opcional)
# =============================================================================
module "sqs_events" {
  source = "./modules/sqs"

  name_prefix                = local.name_prefix
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = var.sqs_message_retention_seconds
  long_polling_wait_seconds  = var.sqs_long_polling_wait_seconds
  create_dlq                 = var.sqs_create_dlq
  dlq_max_receive_count      = var.sqs_dlq_max_receive_count
  tags                       = var.common_tags
}

# =============================================================================
# 6) DYNAMODB: Tabela de eventos ToggleMasterAnalytics + GSIs
# =============================================================================
module "dynamodb_analytics" {
  source = "./modules/dynamodb"

  name_prefix  = local.name_prefix
  billing_mode = var.dynamodb_billing_mode
  create_gsis  = var.dynamodb_create_gsis
  ttl_enabled  = var.dynamodb_ttl_enabled
  tags         = var.common_tags
}

# =============================================================================
# 7) DATA SOURCE: Identidade atual da conta AWS (para montar ARNs de recursos)
# =============================================================================
data "aws_caller_identity" "current" {}

# =============================================================================
# 8) EKS CLUSTER (Sprint 2): Control Plane + Managed Node Group + OIDC Provider
# =============================================================================
module "eks_cluster" {
  source = "./modules/eks_cluster"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  kubernetes_version      = var.eks_kubernetes_version
  node_instance_type      = var.eks_node_instance_type
  node_min_size           = var.eks_node_min_size
  node_desired_size       = var.eks_node_desired_size
  node_max_size           = var.eks_node_max_size
  disk_size_gb            = var.eks_disk_size_gb
  endpoint_public_access  = var.eks_endpoint_public_access
  endpoint_private_access = var.eks_endpoint_private_access

  tags = var.common_tags
}

# =============================================================================
# 9) IAM IRSA (Sprint 2): Roles para pods assumirem via ServiceAccount do K8s
#    Roles: evaluation-pod (SQS send), analytics-pod (SQS recv + Dynamo), keda-operator
# =============================================================================
module "iam_irsa" {
  source = "./modules/iam_irsa"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_issuer_url   = module.eks_cluster.oidc_issuer_url
  aws_account_id    = data.aws_caller_identity.current.account_id

  sqs_events_queue_arn = module.sqs_events.queue_arn
  sqs_dlq_arn          = module.sqs_events.dlq_arn
  dynamodb_table_arn   = module.dynamodb_analytics.table_arn

  tags = var.common_tags
}
