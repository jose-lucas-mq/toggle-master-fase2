#!/usr/bin/env bash
# =============================================================================
# push-all-images-to-ecr.sh
# -----------------------------------------------------------------------------
# Builda as 5 imagens Docker dos microsserviços, faz login no ECR da sua conta
# AWS e faz push de todas para os respectivos repositórios (criados pelo Terraform).
#
# PRE REQUISITOS:
#   • Terraform já aplicado (terraform apply) → repositórios ECR existem.
#   • AWS CLI autenticado (profile default ou AWS_PROFILE setado) com permissão
#     de ecr:GetAuthorizationToken + ecr:InitiateLayerUpload etc (sua role deploy).
#   • Docker rodando localmente.
#
# USO:
#   cd terraform && ./push-all-images-to-ecr.sh
# =============================================================================
set -euo pipefail

# Cores para output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
BOLD='\033[1m'

# Garante que estamos na pasta terraform/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ROOT_DIR="$(cd .. && pwd)"

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}  ToggleMaster — Build & Push das 5 imagens para o ECR          ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo ""

# ----------------------------------------------------------------------------
# 1) Coleta os URLs dos 5 repositórios ECR via terraform output
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[1/5] Coletando URLs dos repositórios ECR do estado Terraform...${NC}"

AUTH_ECR_URL=$(terraform output -raw auth_service_ecr_url)
FLAG_ECR_URL=$(terraform output -raw flag_service_ecr_url)
TARGETING_ECR_URL=$(terraform output -raw targeting_service_ecr_url)
EVALUATION_ECR_URL=$(terraform output -raw evaluation_service_ecr_url)
ANALYTICS_ECR_URL=$(terraform output -raw analytics_service_ecr_url)

echo -e "  • auth-service       → ${GREEN}${AUTH_ECR_URL}${NC}"
echo -e "  • flag-service       → ${GREEN}${FLAG_ECR_URL}${NC}"
echo -e "  • targeting-service  → ${GREEN}${TARGETING_ECR_URL}${NC}"
echo -e "  • evaluation-service → ${GREEN}${EVALUATION_ECR_URL}${NC}"
echo -e "  • analytics-service  → ${GREEN}${ANALYTICS_ECR_URL}${NC}"
echo ""

# Extrai REGIÃO e ACCOUNT_ID do primeiro URL ECR
# Ex: 128432678106.dkr.ecr.us-east-1.amazonaws.com/toggle-master-auth-service
ECR_REGISTRY="${AUTH_ECR_URL%%/*}"
AWS_ACCOUNT_ID="${ECR_REGISTRY%%.*}"
AWS_REGION=$(echo "$ECR_REGISTRY" | sed -n 's/.*ecr\.\([a-z0-9-]*\)\.amazonaws.*/\1/p')
echo -e "  • Conta AWS:  ${AWS_ACCOUNT_ID}"
echo -e "  • Região:     ${AWS_REGION}"
echo -e "  • Registry:   ${ECR_REGISTRY}"
echo ""

# ----------------------------------------------------------------------------
# 2) Login no ECR (docker login usando token temporário do AWS STS)
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[2/5] Fazendo login no ECR via AWS CLI...${NC}"
aws ecr get-login-password --region "$AWS_REGION" | docker login \
  --username AWS \
  --password-stdin "$ECR_REGISTRY"
echo -e "${GREEN}  ✓ Login ECR efetuado com sucesso.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 3) Build + tag + push de cada serviço
# ----------------------------------------------------------------------------
TAG="latest"

build_and_push() {
  local service_name="$1"
  local ecr_url="$2"
  local service_dir="${ROOT_DIR}/${service_name}"

  echo -e "${BLUE}▶ ${service_name}${NC}"
  echo -e "  Buildando imagem local '${service_name}:${TAG}' (linux/amd64, cache reutilizado)..."
  docker build --platform linux/amd64 -t "${service_name}:${TAG}" "$service_dir"

  echo -e "  Tagueando para '${ecr_url}:${TAG}'..."
  docker tag "${service_name}:${TAG}" "${ecr_url}:${TAG}"

  echo -e "  Pushando para o ECR..."
  docker push "${ecr_url}:${TAG}"
  echo -e "${GREEN}  ✓ ${service_name} pushado com sucesso.${NC}"
  echo ""
}

echo -e "${YELLOW}[3/5] Build + Push dos 5 microsserviços...${NC}"
echo ""

build_and_push "auth-service"       "$AUTH_ECR_URL"
build_and_push "flag-service"       "$FLAG_ECR_URL"
build_and_push "targeting-service"  "$TARGETING_ECR_URL"
build_and_push "evaluation-service" "$EVALUATION_ECR_URL"
build_and_push "analytics-service"  "$ANALYTICS_ECR_URL"

# ----------------------------------------------------------------------------
# 4) Resumo final
# ----------------------------------------------------------------------------
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  ✅ Todas as 5 imagens foram buildadas e pushadas para o ECR!${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo ""
echo -e "${YELLOW}Próximos passos (Sprint 2):${NC}"
echo -e "  1) aws eks update-kubeconfig --region ${AWS_REGION} --name toggle-master-eks"
echo -e "  2) kubectl apply -f ../kubernetes/ (namespaces, secrets, configmaps, deployments, services, ingress)"
echo -e "  3) kubectl get pods -n apps -w  (aguardar todos READY 1/1)"
echo -e "  4) curl http://<INGRESS_URL>/auth/health → deve retornar {\"status\":\"ok\"}"
echo ""
