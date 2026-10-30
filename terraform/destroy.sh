#!/usr/bin/env bash
# Script de destroy padrao do time. Atencao: destroi TODOS recursos.
#
# Passos aprendidos (Sprint 2):
#   1. O Nginx Ingress Controller cria um Classic ELB que NAO e gerenciado
#      pelo Terraform. Antes do destroy, deletar o Service para remover o ELB,
#      suas ENIs e Security Groups, senao as sub-redes e o IGW falham com
#      DependencyViolation.
#   2. Os repositorios ECR sao deletados com force_delete=true (definido no
#      modulo terraform/modules/ecr/main.tf), apagando as imagens junto.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Profile AWS configurado em ~/.aws/config (assume a role TerraformDeployRole)
export AWS_PROFILE="${AWS_PROFILE:-toggl}"

echo "⚠️  ESTE SCRIPT DESTROI TODA INFRA DO TOGGLEMASTER AWS! (VPC, RDS, Redis, SQS, DynamoDB, ECR)"
read -r -p "Tem certeza? Escreva DESTROY-TOGGLE-MASTER em maiusculas para confirmar: " confirm

if [[ "$confirm" != "DESTROY-TOGGLE-MASTER" ]]; then
  echo "Cancelado."
  exit 1
fi

# ---------------------------------------------------------------------------
# PASSO 1: Limpar recursos do Kubernetes que NAO sao gerenciados pelo Terraform
# ---------------------------------------------------------------------------
echo ""
echo "==> PASSO 1/3: Limpando recursos do Kubernetes (Ingress / ELB)"
echo "    O Nginx Ingress Controller cria um Classic ELB que bloqueia a delecao"
echo "    das sub-redes e do Internet Gateway se nao for removido antes."

if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  echo "    [OK] kubectl conectado ao cluster"

  # Deleta o Service do ingress-nginx (responsavel pelo ELB)
  if kubectl get svc ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1; then
    echo "    [..] Deletando Service ingress-nginx-controller (remove o ELB)..."
    kubectl delete svc ingress-nginx-controller -n ingress-nginx --timeout=120s || true
  else
    echo "    [--] Service ingress-nginx-controller nao encontrado, pulando."
  fi

  # Deleta todo o namespace ingress-nginx (controller + webhooks)
  if kubectl get ns ingress-nginx >/dev/null 2>&1; then
    echo "    [..] Deletando namespace ingress-nginx..."
    kubectl delete ns ingress-nginx --timeout=120s || true
  fi

  echo "    [..] Aguardando o ELB e suas dependencias serem removidos (30s)..."
  sleep 30
else
  echo "    [!!] kubectl nao conectado ou cluster ja destruido."
  echo "    [!!] Caso o ELB ainda exista, sera removido manualmente no passo 2."
fi

# ---------------------------------------------------------------------------
# PASSO 2: Fallback - remover ELB orfao do Nginx Ingress se ainda existir
# ---------------------------------------------------------------------------
echo ""
echo "==> PASSO 2/3: Verificando ELBs orfaos do Nginx Ingress"

# Pega a VPC do state do Terraform se existir
STATE_VPC=$(terraform state show 'module.networking.aws_vpc.this' 2>/dev/null | grep '^id' | awk '{print $3}' || true)

if [[ -z "$STATE_VPC" ]]; then
  echo "    [--] VPC do ToggleMaster nao encontrada no state, pulando limpeza de ELB."
else
  # Busca todos os Classic ELBs e filtra os que pertencem a VPC do ToggleMaster
  ELB_NAMES=$(aws elb describe-load-balancers \
    --region us-east-1 \
    --query 'LoadBalancerDescriptions[].LoadBalancerName' \
    --output text 2>/dev/null || true)

  for elb in $ELB_NAMES; do
    VPC_ID=$(aws elb describe-load-balancers \
      --region us-east-1 \
      --load-balancer-names "$elb" \
      --query 'LoadBalancerDescriptions[0].VPCId' \
      --output text 2>/dev/null || true)

    if [[ "$VPC_ID" == "$STATE_VPC" ]]; then
      echo "    [..] Deletando ELB orfao $elb (VPC $VPC_ID)..."
      aws elb delete-load-balancer --load-balancer-name "$elb" --region us-east-1 || true
    fi
  done

  echo "    [..] Aguardando limpeza de ENIs e Security Groups (15s)..."
  sleep 15

  # Limpa Security Groups orfaos criados pelo ELB (k8s-elb-*)
  SGS=$(aws ec2 describe-security-groups \
    --region us-east-1 \
    --filters "Name=vpc-id,Values=$STATE_VPC" "Name=group-name,Values=k8s-elb-*" \
    --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true)
  for sg in $SGS; do
    echo "    [..] Deletando SG orfao $sg..."
    aws ec2 delete-security-group --group-id "$sg" --region us-east-1 || true
  done
fi

# ---------------------------------------------------------------------------
# PASSO 3: terraform destroy
# ---------------------------------------------------------------------------
echo ""
echo "==> PASSO 3/3: terraform destroy"
echo "    (ECR force_delete=true apaga as imagens junto com os repositorios)"

terraform init -input=false
terraform destroy -auto-approve

echo ""
echo "✅ Destroy concluido!"
