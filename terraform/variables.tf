variable "aws_region" {
  description = "Região AWS principal do projeto (ex: us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = <<-EOF
    Nome do profile AWS CLI configurado em ~/.aws/config / ~/.aws/credentials.
    Se null/vazio (default), usa o fluxo padrão de credenciais do provider AWS:
      env vars AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN
      OU default profile
      OU role da instância/container (IRSA, ECS, EC2 Instance Role).
    Exemplo: "fiap-toggle-master-role"
  EOF
  type        = string
  default     = null
}

variable "aws_assume_role_arn" {
  description = <<-EOF
    ARN da ROLE ESPECÍFICA da sua conta AWS que o Terraform deve ASSUMIR (sts:AssumeRole)
    para provisionar todos os recursos. Ideal para usar uma role de deploy limitada
    (sem admin full) na sua conta pessoal.

    Se vazio (default), nenhum assume_role é feito e a autenticação depende apenas de
    aws_profile / variáveis de ambiente default.

    Exemplo (coloque a sua):
      "arn:aws:iam::123456789012:role/ToggleMasterDeployRole"
  EOF
  type        = string
  default     = ""
}

variable "aws_assume_role_session_name" {
  description = "Nome da sessão STS usada no assume_role (aparece nos CloudTrail logs)."
  type        = string
  default     = "terraform-toggle-master-local"
}

variable "common_tags" {
  description = "Tags padrão para todos os recursos criados (exceto onde overridden)."
  type        = map(string)
  default = {
    Environment = "dev"
    Team        = "fiap-toggle-master-team"
    Owner       = "tech-challenge-fase2"
    CostCenter  = "fiap-pos-tech"
  }
}

# ------- Networking -------
variable "vpc_cidr" {
  description = "Bloco CIDR principal da VPC dedicada ao ToggleMaster."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Lista de 3 AZs onde recursos Multi-AZ serão criados."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "Lista de 3 blocos CIDR para sub-redes públicas (1 por AZ)."
  type        = list(string)
  default     = ["10.20.0.0/20", "10.20.16.0/20", "10.20.32.0/20"]
}

variable "private_subnet_cidrs" {
  description = "Lista de 3 blocos CIDR para sub-redes privadas (1 por AZ)."
  type        = list(string)
  default     = ["10.20.48.0/20", "10.20.64.0/20", "10.20.80.0/20"]
}

variable "single_nat_gateway" {
  description = "Se true, cria apenas 1 NAT Gateway (economia $). Se false, 1 NAT por AZ (alta disponibilidade)."
  type        = bool
  default     = true
}

# ------- RDS -------
variable "rds_engine_version" {
  type        = string
  default     = "15.4"
  description = "Versão do PostgreSQL. Alinhada ao docker-compose postgres:15-alpine."
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "Classe das 3 instâncias RDS. Free tier elegível = db.t3.micro para contas novas 12 meses."
}

variable "rds_storage_gb" {
  type        = number
  default     = 20
  description = "Tamanho inicial de armazenamento gp3 por instância RDS (GB)."
}

variable "rds_storage_max_gb" {
  type        = number
  default     = 100
  description = "Limite máximo autoscaling de armazenamento por instância RDS."
}

variable "rds_multi_az" {
  type        = bool
  default     = false
  description = "Habilita Multi-AZ (failover automático, custo ~2x). Recomendado false p/ estudo."
}

variable "rds_backup_retention_days" {
  type        = number
  default     = 7
  description = "Dias de retenção de snapshot automático por RDS."
}

# ------- ElastiCache Redis -------
variable "redis_node_type" {
  type        = string
  default     = "cache.t4g.micro"
  description = "Tipo de nó Redis. cache.t4g.micro free tier elegível, cache.t3.micro x86 alternativa."
}

variable "redis_engine_version" {
  type        = string
  default     = "7.0"
  description = "Versão do Redis alinhada com docker-compose redis:7-alpine."
}

# ------- DynamoDB -------
variable "dynamodb_billing_mode" {
  type        = string
  default     = "PAY_PER_REQUEST"
  description = "Modo de cobrança DynamoDB. PAY_PER_REQUEST (On Demand) ideal p/ estudo - custo 0 se sem uso."
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "Valores permitidos: PAY_PER_REQUEST ou PROVISIONED."
  }
}

variable "dynamodb_create_gsis" {
  type        = bool
  default     = true
  description = "Cria GSIs recomendadas p/ consultas analíticas (por flag + user + result)."
}

variable "dynamodb_ttl_enabled" {
  type        = bool
  default     = false
  description = "Habilita TTL no atributo timestamp (expira dados p/ 90 dias - ajustar app p/ emitir epoch)."
}

# ------- SQS -------
variable "sqs_visibility_timeout_seconds" {
  type        = number
  default     = 300
  description = "Tempo (s) que uma mensagem fica invisível após o worker pegar (5min p/ analytics processar 10 batch)."
}

variable "sqs_message_retention_seconds" {
  type        = number
  default     = 345600
  description = "Tempo máximo uma mensagem permanece na fila (padrão 4 dias)."
}

variable "sqs_long_polling_wait_seconds" {
  type        = number
  default     = 20
  description = "Long-polling ReceiveMessage (máximo 20s - reduz chamadas API e custo)."
}

variable "sqs_create_dlq" {
  type        = bool
  default     = true
  description = "Cria fila Dead Letter Queue e política de redrive após N receives (evita poison pill)."
}

variable "sqs_dlq_max_receive_count" {
  type        = number
  default     = 5
  description = "Qtd receives com falha antes da mensagem ir p/ DLQ."
}

# ------- EKS Cluster (Sprint 2) -------
variable "eks_kubernetes_version" {
  type        = string
  default     = "1.31"
  description = "Versão do Kubernetes do cluster EKS (deve ser suportada pela AWS na região)."
}

variable "eks_node_instance_type" {
  type        = string
  default     = "t3.small"
  description = "Tipo de instância EC2 dos nós do Managed Node Group (mínimo t3.small para EKS)."
}

variable "eks_node_min_size" {
  type        = number
  default     = 2
  description = "Número mínimo de nós no ASG do EKS Managed Node Group."
}

variable "eks_node_desired_size" {
  type        = number
  default     = 2
  description = "Número desejado de nós no ASG do EKS Managed Node Group."
}

variable "eks_node_max_size" {
  type        = number
  default     = 4
  description = "Número máximo de nós no ASG do EKS Managed Node Group."
}

variable "eks_disk_size_gb" {
  type        = number
  default     = 20
  description = "Tamanho do disco EBS gp3 de cada nó EKS (GB)."
}

variable "eks_endpoint_public_access" {
  type        = bool
  default     = true
  description = "Habilita acesso público do endpoint da API do Kubernetes (kubectl da sua máquina)."
}

variable "eks_endpoint_private_access" {
  type        = bool
  default     = true
  description = "Habilita acesso privado (dentro da VPC) ao endpoint da API do Kubernetes."
}
