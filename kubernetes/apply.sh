#!/usr/bin/env bash
# =============================================================================
# kubernetes/apply.sh
# -----------------------------------------------------------------------------
# Gera os manifests K8s reais (substitui placeholders {{...}} pelos valores do
# terraform output) e aplica tudo no cluster EKS.
#
# FLUXO DE EXECUCAO:
#   1) Verifica kubectl conectado ao toggle-master-eks
#   2) Coleta outputs do Terraform (RDS, Redis, SQS, ECR, IRSA)
#   3) Le MASTER_KEY do .env local (nao vem do Terraform)
#   4) Gera os manifests (.gen.yaml) a partir dos templates
#   5) Bootstrap: instala o Nginx Ingress Controller (cria o LoadBalancer publico)
#   6) Deploy do namespace + serviceaccounts + configmap + secrets + auth-service
#   7) Inicializa as tabelas nos 3 RDS (init.sql, idempotente)
#   8) Port-forward no auth e POST /admin/keys para gerar SERVICE_API_KEY
#   9) Atualiza o Secret K8s com a SERVICE_API_KEY gerada
#  10) Deploy dos demais servicos + Ingress + autoscaling (HPA/KEDA)
#
# PRE REQUISITOS:
#   - terraform apply ja rodou (state tem os valores)
#   - kubectl configurado (aws eks update-kubeconfig ...)
#   - kubectl apontando para o cluster toggle-master-eks
#   - helm instalado (usado no bootstrap do Nginx Ingress Controller)
#   - Arquivo ../.env com MASTER_KEY definido
#
# USO:
#   cd kubernetes && ./apply.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Profile AWS que assume a role que criou o cluster EKS.
# Sem isso o kubectl usa as credenciais do "default" (terraform-service-user),
# que NAO tem acesso ao cluster -> "the server has asked for the client to provide credentials".
export AWS_PROFILE="${AWS_PROFILE:-toggl}"

TF_DIR="../terraform"
ENV_FILE="../.env"

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}  ToggleMaster — Deploy dos manifests no EKS                   ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo ""

# ----------------------------------------------------------------------------
# 1) Verifica kubectl conectado ao cluster certo
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[1/10] Verificando conexao kubectl com o cluster...${NC}"
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "NONE")
echo -e "  Contexto atual: ${BLUE}${CURRENT_CONTEXT}${NC}"
if [[ "$CURRENT_CONTEXT" != *"toggle-master-eks"* ]]; then
  echo -e "${RED}  Aviso: Contexto NAO e o toggle-master-eks!${NC}"
  echo -e "  Rode: aws eks update-kubeconfig --region us-east-1 --name toggle-master-eks"
  read -rp "  Continuar mesmo assim? (s/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[sS]$ ]]; then echo "Abortado."; exit 1; fi
fi
echo ""

# ----------------------------------------------------------------------------
# 2) Coleta outputs do Terraform
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[2/10] Coletando valores do estado Terraform...${NC}"
cd "$TF_DIR"

AUTH_RDS_ENDPOINT=$(terraform output -raw auth_rds_endpoint)
FLAGS_RDS_ENDPOINT=$(terraform output -raw flags_rds_endpoint)
TARGETING_RDS_ENDPOINT=$(terraform output -raw targeting_rds_endpoint)
REDIS_ENDPOINT_ADDRESS=$(terraform output -raw redis_endpoint_address)
REDIS_PORT=$(terraform output -raw redis_port)
SQS_EVENTS_URL=$(terraform output -raw sqs_events_url)

AUTH_RDS_PASSWORD=$(terraform output -raw auth_rds_password)
FLAGS_RDS_PASSWORD=$(terraform output -raw flags_rds_password)
TARGETING_RDS_PASSWORD=$(terraform output -raw targeting_rds_password)

IRSA_EVALUATION_ROLE_ARN=$(terraform output -raw irsa_evaluation_role_arn)
IRSA_ANALYTICS_ROLE_ARN=$(terraform output -raw irsa_analytics_role_arn)
IRSA_KEDA_ROLE_ARN=$(terraform output -raw irsa_keda_role_arn)

AUTH_ECR_URL=$(terraform output -raw auth_service_ecr_url)
FLAG_ECR_URL=$(terraform output -raw flag_service_ecr_url)
TARGETING_ECR_URL=$(terraform output -raw targeting_service_ecr_url)
EVALUATION_ECR_URL=$(terraform output -raw evaluation_service_ecr_url)
ANALYTICS_ECR_URL=$(terraform output -raw analytics_service_ecr_url)

cd "$SCRIPT_DIR"
echo -e "${GREEN}  ✓ Valores coletados.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 3) Le MASTER_KEY do .env local
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[3/10] Lendo MASTER_KEY do ${ENV_FILE}...${NC}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}  ERRO: Arquivo ${ENV_FILE} nao encontrado.${NC}"
  exit 1
fi

MASTER_KEY=$(grep -E '^MASTER_KEY=' "$ENV_FILE" | head -1 | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'")
if [[ -z "$MASTER_KEY" ]]; then
  echo -e "${RED}  ERRO: MASTER_KEY nao definido em ${ENV_FILE}.${NC}"
  exit 1
fi
echo -e "${GREEN}  ✓ MASTER_KEY carregado.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 3b) Codifica segredos em base64 (SERVICE_API_KEY sera gerada depois)
# ----------------------------------------------------------------------------
B64() { echo -n "$1" | base64; }

AUTH_RDS_PASSWORD_B64=$(B64 "$AUTH_RDS_PASSWORD")
FLAGS_RDS_PASSWORD_B64=$(B64 "$FLAGS_RDS_PASSWORD")
TARGETING_RDS_PASSWORD_B64=$(B64 "$TARGETING_RDS_PASSWORD")
MASTER_KEY_B64=$(B64 "$MASTER_KEY")
# Placeholder temporario para SERVICE_API_KEY (sera atualizada no passo 9)
SERVICE_API_KEY_B64=$(B64 "PLACEHOLDER")

# ----------------------------------------------------------------------------
# 4) Gera os manifests (.gen.yaml) a partir dos templates
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[4/10] Gerando manifests (.gen.yaml) com valores do TF...${NC}"

generate() {
  local src="$1"
  local dst="${src%.yaml}.gen.yaml"
  local tmp
  tmp=$(cat "$src")
  tmp=$(echo "$tmp" | sed "s|{{AUTH_RDS_ENDPOINT}}|${AUTH_RDS_ENDPOINT}|g")
  tmp=$(echo "$tmp" | sed "s|{{FLAGS_RDS_ENDPOINT}}|${FLAGS_RDS_ENDPOINT}|g")
  tmp=$(echo "$tmp" | sed "s|{{TARGETING_RDS_ENDPOINT}}|${TARGETING_RDS_ENDPOINT}|g")
  tmp=$(echo "$tmp" | sed "s|{{REDIS_ENDPOINT_ADDRESS}}|${REDIS_ENDPOINT_ADDRESS}|g")
  tmp=$(echo "$tmp" | sed "s|{{REDIS_PORT}}|${REDIS_PORT}|g")
  tmp=$(echo "$tmp" | sed "s|{{SQS_EVENTS_URL}}|${SQS_EVENTS_URL}|g")
  tmp=$(echo "$tmp" | sed "s|{{AUTH_RDS_PASSWORD_B64}}|${AUTH_RDS_PASSWORD_B64}|g")
  tmp=$(echo "$tmp" | sed "s|{{FLAGS_RDS_PASSWORD_B64}}|${FLAGS_RDS_PASSWORD_B64}|g")
  tmp=$(echo "$tmp" | sed "s|{{TARGETING_RDS_PASSWORD_B64}}|${TARGETING_RDS_PASSWORD_B64}|g")
  tmp=$(echo "$tmp" | sed "s|{{MASTER_KEY_B64}}|${MASTER_KEY_B64}|g")
  tmp=$(echo "$tmp" | sed "s|{{SERVICE_API_KEY_B64}}|${SERVICE_API_KEY_B64}|g")
  tmp=$(echo "$tmp" | sed "s|{{IRSA_EVALUATION_ROLE_ARN}}|${IRSA_EVALUATION_ROLE_ARN}|g")
  tmp=$(echo "$tmp" | sed "s|{{IRSA_ANALYTICS_ROLE_ARN}}|${IRSA_ANALYTICS_ROLE_ARN}|g")
  tmp=$(echo "$tmp" | sed "s|{{IRSA_KEDA_ROLE_ARN}}|${IRSA_KEDA_ROLE_ARN}|g")
  tmp=$(echo "$tmp" | sed "s|{{AUTH_ECR_URL}}|${AUTH_ECR_URL}|g")
  tmp=$(echo "$tmp" | sed "s|{{FLAG_ECR_URL}}|${FLAG_ECR_URL}|g")
  tmp=$(echo "$tmp" | sed "s|{{TARGETING_ECR_URL}}|${TARGETING_ECR_URL}|g")
  tmp=$(echo "$tmp" | sed "s|{{EVALUATION_ECR_URL}}|${EVALUATION_ECR_URL}|g")
  tmp=$(echo "$tmp" | sed "s|{{ANALYTICS_ECR_URL}}|${ANALYTICS_ECR_URL}|g")
  echo "$tmp" > "$dst"
  echo -e "  ✓ ${src} → ${dst}"
}

generate namespaces.yaml
generate serviceaccounts.yaml
generate configmap.yaml
generate secrets.template.yaml
generate auth-service.yaml
generate flag-service.yaml
generate targeting-service.yaml
generate evaluation-service.yaml
generate analytics-service.yaml
generate ingress.yaml
# --- Sprint 3: autoscaling ---
generate hpa-evaluation.yaml
generate keda-scaledobject.yaml

echo ""

# ----------------------------------------------------------------------------
# 5) Bootstrap: Nginx Ingress Controller
#    Nao e gerenciado pelo Terraform (nasce do Helm), entao precisa ser
#    reinstalado toda vez que o cluster EKS e recriado do zero.
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[5/10] Bootstrap: Nginx Ingress Controller...${NC}"

if kubectl -n ingress-nginx get deployment ingress-nginx-controller >/dev/null 2>&1; then
  echo -e "${GREEN}  ✓ Nginx Ingress Controller ja instalado.${NC}"
elif ! command -v helm >/dev/null 2>&1; then
  echo -e "${RED}  ERRO: helm nao encontrado e o Ingress Controller nao esta instalado.${NC}"
  echo -e "  Instale o helm: brew install helm"
  exit 1
else
  echo -e "  Instalando via Helm (cria um LoadBalancer publico na AWS)..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.service.type=LoadBalancer >/dev/null
  kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s
  echo -e "${GREEN}  ✓ Nginx Ingress Controller instalado.${NC}"
fi
echo ""

# ----------------------------------------------------------------------------
# 6) Aplica namespace + serviceaccounts + configmap + secrets + auth-service
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[6/10] Aplicando base: namespace, SA, configmap, secrets, auth-service...${NC}"
echo ""

kubectl apply -f namespaces.gen.yaml
kubectl apply -f serviceaccounts.gen.yaml
kubectl apply -f configmap.gen.yaml
kubectl apply -f secrets.template.gen.yaml
kubectl apply -f auth-service.gen.yaml

echo ""
echo -e "  Aguardando auth-service ficar READY..."
kubectl -n apps rollout status deployment/auth-service --timeout=180s
echo -e "${GREEN}  ✓ auth-service pronto.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 7) Inicializa as tabelas nos 3 RDS (init.sql)
#    O RDS nasce VAZIO: sem isso o POST /admin/keys falha com 500
#    ("Erro ao salvar a chave"), pois a tabela api_keys nao existe.
#    Os init.sql usam CREATE TABLE IF NOT EXISTS -> idempotente.
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[7/10] Inicializando tabelas nos RDS (init.sql)...${NC}"

init_rds() {
  local svc="$1" user="$2" db="$3" pass="$4" endpoint="$5" sqlfile="$6"
  local host="${endpoint%%:*}"
  # Remove pod temporario remanescente de uma execucao anterior interrompida
  kubectl -n apps delete pod "psql-init-${svc}" --ignore-not-found >/dev/null 2>&1 || true
  kubectl run "psql-init-${svc}" --rm -i --restart=Never -n apps \
    --image=postgres:15-alpine \
    -- env PGPASSWORD="$pass" psql -h "$host" -U "$user" -d "$db" -f - < "$sqlfile" >/dev/null
}

RDS_BASE="${SCRIPT_DIR}/.."
init_rds auth      auth_user      auth_db      "$AUTH_RDS_PASSWORD"      "$AUTH_RDS_ENDPOINT"      "${RDS_BASE}/auth-service/db/init.sql"      || {
  echo -e "${RED}  ERRO: falha ao inicializar o banco auth_db.${NC}"; exit 1; }
echo -e "${GREEN}  ✓ auth_db pronto.${NC}"
init_rds flags     flag_user      flags_db     "$FLAGS_RDS_PASSWORD"     "$FLAGS_RDS_ENDPOINT"     "${RDS_BASE}/flag-service/db/init.sql"      || {
  echo -e "${RED}  ERRO: falha ao inicializar o banco flags_db.${NC}"; exit 1; }
echo -e "${GREEN}  ✓ flags_db pronto.${NC}"
init_rds targeting targeting_user targeting_db "$TARGETING_RDS_PASSWORD" "$TARGETING_RDS_ENDPOINT" "${RDS_BASE}/targeting-service/db/init.sql" || {
  echo -e "${RED}  ERRO: falha ao inicializar o banco targeting_db.${NC}"; exit 1; }
echo -e "${GREEN}  ✓ targeting_db pronto.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 8) Port-forward + POST /admin/keys para gerar SERVICE_API_KEY
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[8/10] Gerando SERVICE_API_KEY via POST /admin/keys no auth-service...${NC}"

# Port-forward em background
kubectl -n apps port-forward svc/auth-service 18001:8001 >/dev/null 2>&1 &
PF_PID=$!

# Aguarda o port-forward ficar disponivel
for i in $(seq 1 20); do
  if curl -s http://localhost:18001/health >/dev/null 2>&1; then break; fi
  sleep 1
done

# Cria a chave de servico
CREATE_RESPONSE=$(curl -s -X POST http://localhost:18001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -d '{"name": "kubernetes-services"}')

# Para o port-forward
kill "$PF_PID" 2>/dev/null || true
wait "$PF_PID" 2>/dev/null || true

# Extrai a chave do JSON (usa python3, universal no macOS)
SERVICE_API_KEY=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])" 2>/dev/null)

if [[ -z "$SERVICE_API_KEY" || "$SERVICE_API_KEY" == "None" ]]; then
  echo -e "${RED}  ERRO ao gerar SERVICE_API_KEY. Resposta: ${CREATE_RESPONSE}${NC}"
  exit 1
fi

echo -e "${GREEN}  ✓ SERVICE_API_KEY gerada: ${SERVICE_API_KEY:0:20}...${NC}"
echo ""

# ----------------------------------------------------------------------------
# 9) Atualiza o Secret K8s com a SERVICE_API_KEY real
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[9/10] Atualizando Secret com a SERVICE_API_KEY real...${NC}"

SERVICE_API_KEY_B64=$(B64 "$SERVICE_API_KEY")

# Patch no secret (atualiza apenas o campo SERVICE_API_KEY)
kubectl -n apps patch secret togglemaster-secrets \
  --type=json \
  -p="[{\"op\":\"replace\",\"path\":\"/data/SERVICE_API_KEY\",\"value\":\"${SERVICE_API_KEY_B64}\"}]"

echo -e "${GREEN}  ✓ Secret atualizado.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 10) Aplica os demais servicos + ingress
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[10/10] Aplicando servicos restantes + ingress...${NC}"
echo ""

kubectl apply -f flag-service.gen.yaml
kubectl apply -f targeting-service.gen.yaml
kubectl apply -f evaluation-service.gen.yaml
kubectl apply -f analytics-service.gen.yaml
kubectl apply -f ingress.gen.yaml

echo ""
echo -e "  Aguardando todos os deployments ficarem READY..."
kubectl -n apps rollout status deployment/flag-service --timeout=180s
kubectl -n apps rollout status deployment/targeting-service --timeout=180s
kubectl -n apps rollout status deployment/evaluation-service --timeout=180s
kubectl -n apps rollout status deployment/analytics-service --timeout=180s

# ----------------------------------------------------------------------------
# Sprint 3: HPA (evaluation) + KEDA ScaledObject (analytics)
# ----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}  Autoscaling: HPA (evaluation) + KEDA (analytics)...${NC}"
echo ""

# HPA do evaluation — requer Metrics Server
if kubectl get apiservice v1beta1.metrics.k8s.io >/dev/null 2>&1; then
  kubectl apply -f hpa-evaluation.gen.yaml
  echo -e "${GREEN}  ✓ HPA do evaluation aplicado.${NC}"
else
  echo -e "${YELLOW}  ! Metrics Server nao detectado. HPA sera aplicado, mas ficara sem metricas.${NC}"
  echo -e "${YELLOW}    Rode: ./install-keda.sh (instala Metrics Server + KEDA)${NC}"
  kubectl apply -f hpa-evaluation.gen.yaml
fi

# KEDA ScaledObject do analytics — requer CRDs do KEDA
if kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1; then
  kubectl apply -f keda-scaledobject.gen.yaml
  echo -e "${GREEN}  ✓ KEDA ScaledObject do analytics aplicado.${NC}"
else
  echo -e "${YELLOW}  ! CRDs do KEDA nao encontrados. Pulando o ScaledObject.${NC}"
  echo -e "${YELLOW}    Rode: ./install-keda.sh e depois re-execute ./apply.sh${NC}"
fi

echo ""
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  Deploy concluido! Todos os 5 servicos estao no ar.             ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo ""
echo -e "${YELLOW}Verificacoes rapidas:${NC}"
echo "  kubectl get pods -n apps"
echo "  kubectl get ingress -n apps"
echo "  kubectl get sa -n apps"
echo "  kubectl get hpa -n apps"
echo "  kubectl get scaledobject -n apps"
echo ""
echo -e "${YELLOW}Proximos passos:${NC}"
echo "  - Instalar autoscaling (Metrics Server + KEDA):"
echo "    ./install-keda.sh"
echo "  - Testar HPA + KEDA sob carga:"
echo "    ../scripts/load-test-evaluation.sh <INGRESS_URL>"
echo "    ../scripts/send-sqs-batch.sh 1000"
echo ""
