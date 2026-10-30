output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN do cluster EKS."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Endpoint público da API do Kubernetes (usado pelo kubectl)."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Versão do Kubernetes rodando no cluster."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = "ID do Security Group do Control Plane EKS (criado automaticamente pela AWS)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID do Security Group dos nós workers."
  value       = aws_security_group.nodes.id
}

output "node_role_arn" {
  description = "ARN da role IAM dos nós workers (Managed Node Group)."
  value       = aws_iam_role.nodes.arn
}

output "node_role_name" {
  description = "Nome da role IAM dos nós workers."
  value       = aws_iam_role.nodes.name
}

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider do cluster (usado para montar Trust Policy das roles IRSA dos pods)."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_issuer_url" {
  description = "URL do issuer OIDC do cluster (ex: https://oidc.eks.us-east-1.amazonaws.com/id/XXXXX)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "kubeconfig_command" {
  description = "Comando para configurar o kubectl local para acessar o cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}
