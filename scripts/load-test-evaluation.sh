#!/usr/bin/env bash
# =============================================================================
# scripts/load-test-evaluation.sh
# -----------------------------------------------------------------------------
# Gera carga HTTP no evaluation-service para disparar o HPA (T3.2).
#
# Cada requisição /evaluate também publica um evento no SQS, então este script
# serve para DOIS testes:
#   - HPA do evaluation escalando por CPU
#   - KEDA do analytics escalando pela profundidade da fila SQS
#
# USO:
#   ./load-test-evaluation.sh <INGRESS_URL> [DURACAO] [CONCORRENCIA]
#
# Exemplos:
#   ./load-test-evaluation.sh http://abc123.us-east-1.elb.amazonaws.com
#   ./load-test-evaluation.sh http://abc123.us-east-1.elb.amazonaws.com 120s 50
#
# REQUISITOS:
#   - Recomendado ter `hey` (brew install hey) ou `ab` (ApacheBench).
#     Sem eles, usa um fallback em bash+curl.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

# ----------------------------------------------------------------------------
# Argumentos
# ----------------------------------------------------------------------------
INGRESS_URL="${1:-}"
DURATION="${2:-60s}"
CONCURRENCY="${3:-30}"

if [[ -z "$INGRESS_URL" ]]; then
  echo -e "${RED}Uso: $0 <INGRESS_URL> [DURACAO] [CONCORRENCIA]${NC}"
  echo "Ex.: $0 http://abc123.us-east-1.elb.amazonaws.com 60s 30"
  exit 1
fi
# Remove barra final
INGRESS_URL="${INGRESS_URL%/}"

FLAG_NAME="${FLAG_NAME:-load-test-flag}"

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}  ToggleMaster — Load Test do evaluation-service (HPA)          ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "  Ingress .......: ${INGRESS_URL}"
echo -e "  Duracao .......: ${DURATION}"
echo -e "  Concorrencia ..: ${CONCURRENCY}"
echo -e "  Flag ..........: ${FLAG_NAME}"
echo ""

# ----------------------------------------------------------------------------
# 1) Prepara flag + regra (para o /evaluate retornar dados reais)
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[1/3] Preparando flag + regra de teste...${NC}"

MASTER_KEY=""
if [[ -f "$ENV_FILE" ]]; then
  MASTER_KEY=$(grep -E '^MASTER_KEY=' "$ENV_FILE" | head -1 | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'")
fi
MASTER_KEY="${MASTER_KEY:-SUA_MASTER_KEY}"

# Cria (ou reaproveita) uma API key de servico
KEY_RESP=$(curl -s -X POST "${INGRESS_URL}/auth/admin/keys" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -d '{"name": "load-test"}' || true)
API_KEY=$(echo "$KEY_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || true)

if [[ -z "$API_KEY" ]]; then
  echo -e "${YELLOW}  ! Nao foi possivel criar uma key nova (talvez ja exista). Prosseguindo.${NC}"
  API_KEY="${API_KEY_OVERRIDE:-}"
fi

if [[ -n "$API_KEY" ]]; then
  # Cria a flag (ignora erro se ja existir)
  curl -s -X POST "${INGRESS_URL}/flags" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d "{\"name\": \"${FLAG_NAME}\", \"description\": \"flag de teste de carga\", \"is_enabled\": true}" \
    >/dev/null || true

  # Cria a regra PERCENTAGE 50% (ignora erro se ja existir)
  curl -s -X POST "${INGRESS_URL}/rules" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${API_KEY}" \
    -d "{\"flag_name\": \"${FLAG_NAME}\", \"is_enabled\": true, \"rules\": {\"type\": \"PERCENTAGE\", \"value\": 50}}" \
    >/dev/null || true

  echo -e "${GREEN}  ✓ Flag '${FLAG_NAME}' + regra prontas.${NC}"
else
  echo -e "${YELLOW}  ! Pulando criacao de flag (sem API key).${NC}"
fi
echo ""

# ----------------------------------------------------------------------------
# 2) Confirma que /evaluate responde
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[2/3] Testando /evaluate...${NC}"
TEST_RESP=$(curl -s "${INGRESS_URL}/evaluate?user_id=load-tester&flag_name=${FLAG_NAME}" || true)
echo -e "  Resposta: ${TEST_RESP}"
echo ""

# ----------------------------------------------------------------------------
# 3) Dispara a carga
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[3/3] Disparando carga...${NC}"
echo -e "  Abra OUTRO terminal e rode: ${BLUE}kubectl get hpa -n apps -w${NC}"
echo ""

URL="${INGRESS_URL}/evaluate?user_id=load-\$RANDOM&flag_name=${FLAG_NAME}"

if command -v hey >/dev/null 2>&1; then
  echo -e "${GREEN}  Usando 'hey'...${NC}"
  hey -z "$DURATION" -c "$CONCURRENCY" "$URL"

elif command -v ab >/dev/null 2>&1; then
  # ab nao suporta variaveis; usa user_id fixo (suficiente p/ CPU)
  echo -e "${GREEN}  Usando 'ab' (ApacheBench)...${NC}"
  N_REQ=$(( CONCURRENCY * 200 ))
  ab -n "$N_REQ" -c "$CONCURRENCY" "${INGRESS_URL}/evaluate?user_id=load-user&flag_name=${FLAG_NAME}"

else
  echo -e "${YELLOW}  'hey'/'ab' nao encontrados. Usando fallback bash+curl.${NC}"
  echo -e "${YELLOW}  (instale 'hey' com: brew install hey — faz um teste bem melhor)${NC}"
  END=$(( $(date +%s) + ${DURATION%s} ))
  TOTAL=0
  while [[ $(date +%s) -lt $END ]]; do
    for _ in $(seq 1 "$CONCURRENCY"); do
      curl -s -o /dev/null "${INGRESS_URL}/evaluate?user_id=load-${RANDOM}&flag_name=${FLAG_NAME}" &
    done
    wait
    TOTAL=$(( TOTAL + CONCURRENCY ))
    printf "\r  Requisicoes enviadas: %d" "$TOTAL"
  done
  echo ""
fi

echo ""
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  Carga finalizada!                                             ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo ""
echo -e "${YELLOW}O que observar agora:${NC}"
echo "  kubectl get hpa -n apps                  # evaluation subiu de 2 p/ mais"
echo "  kubectl get pods -n apps -w              # novas replicas do evaluation"
echo "  kubectl get pods -n apps -w              # analytics escalando via KEDA (SQS)"
echo "  aws sqs get-queue-attributes --queue-url <URL> --attribute-names ApproximateNumberOfMessages"
echo ""
echo -e "${YELLOW}Dica:${NC} aguarde ~2 min apos parar a carga para ver o scale-down."
echo ""
