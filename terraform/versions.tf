terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  assume_role {
    # Apenas assume a role se a variável aws_assume_role_arn for setada (não vazia).
    # Deixar "" (default) significa "sem assume_role" (usa credenciais do profile ou env vars).
    role_arn     = length(var.aws_assume_role_arn) > 0 ? var.aws_assume_role_arn : null
    session_name = var.aws_assume_role_session_name

    # Duração máxima da sessão STS (padrão 3600s = 1h; formatos aceitos "1h", "30m", "90m" etc).
    # Não aumente além do máximo permitido pela role (ver "Maximum CLI/API session duration" na role).
    duration = "1h"
  }

  default_tags {
    tags = merge(var.common_tags, {
      ManagedBy = "Terraform"
      Project   = "ToggleMaster"
    })
  }
}

provider "random" {}
provider "tls" {}
