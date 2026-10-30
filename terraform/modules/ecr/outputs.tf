output "repo_arns" {
  description = "Map name (SEM prefixo toggle-master-) → ARN de cada repositório."
  value       = { for idx, r in aws_ecr_repository.this : var.repos[idx].name => r.arn }
}
output "repo_urls" {
  description = "Map name (SEM prefixo toggle-master-) → URL do repositório. Ex: 123.dkr.ecr.us-east-1.amazonaws.com/auth-service"
  value       = { for idx, r in aws_ecr_repository.this : var.repos[idx].name => r.repository_url }
}
output "registry_id" { value = aws_ecr_repository.this[0].registry_id }
