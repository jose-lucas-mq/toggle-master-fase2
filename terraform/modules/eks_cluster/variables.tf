variable "name_prefix" {
  description = "Prefixo para nomes dos recursos EKS (ex: toggle-master)."
  type        = string
}

variable "aws_region" {
  description = "Região AWS do cluster EKS."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID da VPC onde o cluster EKS será criado."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das 3 sub-redes privadas (onde vão os nós workers - Well Architected)."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs das 3 sub-redes públicas (usadas para endpoint público do control plane e ALB do Ingress)."
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes (deve ser suportada pelo EKS na região)."
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "Tipo de instância EC2 dos nós do Managed Node Group."
  type        = string
  default     = "t3.small"
}

variable "node_min_size" {
  description = "Número mínimo de nós no ASG do MNG."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Número desejado de nós no ASG do MNG."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Número máximo de nós no ASG do MNG."
  type        = number
  default     = 4
}

variable "disk_size_gb" {
  description = "Tamanho do disco EBS gp3 de cada nó (GB)."
  type        = number
  default     = 20
}

variable "endpoint_public_access" {
  description = "Habilita acesso público ao endpoint da API do Kubernetes (kubectl da sua máquina)."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Habilita acesso privado (dentro da VPC) ao endpoint da API do Kubernetes."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags padrão dos recursos."
  type        = map(string)
  default     = {}
}
