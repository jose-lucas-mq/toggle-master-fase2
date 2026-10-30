# =============================================================================
# Backend Terraform (Estado Compartilhado S3)
# =============================================================================
# Armazena o terraform.tfstate em um BUCKET S3 da SUA CONTA AWS pessoal.
#
# Dados da SUA CONTA (setados manualmente):
#   Conta AWS:            128432678106
#   ARN Bucket S3:        arn:aws:s3:::fiap-tf-state-5dclt
#   Pasta no Bucket (key prefix): -fase-2/
#   Região:               us-east-1
#   Role usada p/ acessar bucket (mesma role de deploy, consistência):
#                          arn:aws:iam::128432678106:role/TerraformDeployRole
# =============================================================================

terraform {
  backend "s3" {
    # ------------------------------------------------------------------
    # Bucket e Key (pasta + arquivo tfstate)
    # ------------------------------------------------------------------
    bucket = "fiap-tf-state-5dclt"
    key    = "-fase-2/terraform.tfstate"
    region = "us-east-1"

    # ------------------------------------------------------------------
    # Autenticação do backend S3
    # ------------------------------------------------------------------
    # 1) Profile base com credenciais LONG-TERM do user terraform-service-user
    #    (só tem permissão sts:AssumeRole na role acima).
    profile = "default"

    # 2) AssumeRole: usa a MESMA role de deploy para tudo (estado S3 + recursos)
    #    -> Princípio do menor privilégio consistente.
    role_arn     = "arn:aws:iam::128432678106:role/TerraformDeployRole"
    session_name = "terraform-toggle-master-backend-s3"

    # Criptografia padrão SSE-S3 em repouso (sem custo extra)
    encrypt = true
  }
}
