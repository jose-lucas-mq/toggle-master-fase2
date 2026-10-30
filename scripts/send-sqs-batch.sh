#!/usr/bin/env bash
# =============================================================================
# scripts/send-sqs-batch.sh
# -----------------------------------------------------------------------------
# Envia N mensagens em lote para a fila SQS (toggle-master-events) para disparar
# o KEDA, que escala o analytics-service de 0 -> N conforme a profundidade
# da fila (T3.3 / T3.4).
#
# O corpo da mensagem segue o mesmo formato publicado pelo evaluation-service:
#   {"user_id": "...", "flag_name": "...", "result": <bool>, "timestamp": "..."}
#
# USO:
#   ./send-sqs-batch.sh [QUANTIDADE] [TAMANHO_LOTE]
#
# Exemplos:
#   ./send-sqs-batch.sh            # 500 mensagens, lotes de 10
#   ./send-sqs-batch.sh 2000 10    # 2000 mensagens, lotes de 10 (max AWS)
#
# Fonte da URL da fila (nessa ordem):
#   1) variavel SQS_URL
#   2) terraform output sqs_events_url (../terraform)
# REQUISITOS: aws cli configurado (profile toggl) + jq opcional.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"

export AWS_PROFILE="${AWS_PROFILE:-toggl}"
REGION="${AWS_REGION:-us-east-1}"

TOTAL="${1:-500}"
BATCH="${2:-10}"   # AWS send-message-batch aceita no maximo 10

if [[ "$BATCH" -gt 10 ]]; then
  echo -e "${YELLOW}! Lote maximo da AWS e 10. Ajustando de ${BATCH} para 10.${NC}"
  BATCH=10
fi

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}  ToggleMaster — Envio de mensagens em lote para o SQS (KEDA)   ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "  Total de mensagens .: ${TOTAL}"
echo -e "  Tamanho do lote ....: ${BATCH}"
echo ""

# ----------------------------------------------------------------------------
# 1) Descobre a URL da fila
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[1/2] Descobrindo URL da fila SQS...${NC}"
SQS_URL="${SQS_URL:-}"
if [[ -z "$SQS_URL" && -d "$TF_DIR" ]]; then
  SQS_URL=$(cd "$TF_DIR" && terraform output -raw sqs_events_url 2>/dev/null || true)
fi
if [[ -z "$SQS_URL" ]]; then
  echo -e "${RED}ERRO: nao foi possivel determinar a URL da fila.${NC}"
  echo "Defina SQS_URL=... ou garanta que 'terraform output sqs_events_url' funciona."
  exit 1
fi
echo -e "${GREEN}  ✓ Fila: ${SQS_URL}${NC}"
echo ""

# ----------------------------------------------------------------------------
# 2) Envia em lotes
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[2/2] Enviando ${TOTAL} mensagens em lotes de ${BATCH}...${NC}"
echo -e "  Abra OUTRO terminal e rode: ${BLUE}kubectl get pods -n apps -w${NC}"
echo ""

SENT=0
FAILED=0

# Monta o arquivo JSON de entrada de um lote (10 entries)
build_batch_json() {
  local count="$1" offset="$2"
  python3 - "$count" "$offset" <<'PY'
import json, sys, uuid, random, datetime
count = int(sys.argv[1]); offset = int(sys.argv[2])
entries = []
for i in range(count):
    n = offset + i
    body = {
        "user_id": f"batch-user-{n}",
        "flag_name": "load-test-flag",
        "result": random.random() < 0.5,
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    entries.append({"Id": str(uuid.uuid4()), "MessageBody": json.dumps(body)})
print(json.dumps(entries))
PY
}

while [[ $SENT -lt $TOTAL ]]; do
  REMAINING=$(( TOTAL - SENT ))
  THIS_BATCH=$(( REMAINING < BATCH ? REMAINING : BATCH ))

  ENTRIES=$(build_batch_json "$THIS_BATCH" "$SENT")

  if aws sqs send-message-batch \
      --queue-url "$SQS_URL" \
      --entries "$ENTRIES" \
      --region "$REGION" >/dev/null 2>&1; then
    SENT=$(( SENT + THIS_BATCH ))
    printf "\r  Enviadas: %d / %d" "$SENT" "$TOTAL"
  else
    FAILED=$(( FAILED + THIS_BATCH ))
    printf "\r  Falha em um lote (enviadas: %d / %d)" "$SENT" "$TOTAL"
    sleep 1
  fi
done
echo ""
echo ""

# ----------------------------------------------------------------------------
# Resumo + metricas da fila
# ----------------------------------------------------------------------------
echo -e "${GREEN}  ✓ Envio concluido. Enviadas: ${SENT} | Falhas: ${FAILED}${NC}"
echo ""

QUEUE_NAME=$(basename "$SQS_URL")
ATTRS=$(aws sqs get-queue-attributes \
  --queue-url "$SQS_URL" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --region "$REGION" --output json 2>/dev/null || true)

echo -e "${YELLOW}Estado atual da fila (${QUEUE_NAME}):${NC}"
echo "$ATTRS" | python3 -c "import sys,json; d=json.load(sys.stdin).get('Attributes',{}); print(f\"  Visiveis ....: {d.get('ApproximateNumberOfMessages','?')}\"); print(f\"  Em voo ......: {d.get('ApproximateNumberOfMessagesNotVisible','?')}\")" 2>/dev/null || echo "  (nao foi possivel ler atributos)"
echo ""
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  Lote enviado! Observe o KEDA escalar o analytics.            ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo ""
echo -e "${YELLOW}O que observar agora:${NC}"
echo "  kubectl get scaledobject -n apps         # READY=True, ACTIVE=True"
echo "  kubectl get pods -n apps -w              # analytics subindo de 0 -> N"
echo "  kubectl get hpa -n apps                  # keda-hpa-analytics-scaledobject"
echo "  aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT --region ${REGION}"
echo ""
