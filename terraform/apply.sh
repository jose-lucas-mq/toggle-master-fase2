#!/usr/bin/env bash
# Script de apply padrão para o time.
# - Sempre executa fmt, init, plan e, se o usuário aprovar, apply.
set -euo pipefail

# ---------- Cores para terminal ----------
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> [1/4] terraform fmt -recursive"
terraform fmt -recursive

echo "==> [2/4] terraform init (backend S3 configurado diretamente em backend.tf)"
terraform init -input=false

echo "==> [3/4] terraform plan (salvo em tfplan.binary)"
terraform plan -out=tfplan.binary -input=false

echo ""
echo -e "${BOLD}${RED}"
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║  ⛔  ATENÇÃO OBRIGATÓRIA!                                                    ║"
echo "╠══════════════════════════════════════════════════════════════════════════════╣"
echo "║  Esta infra custa APROXIMADAMENTE US$ 0,80/mês (stack EFÊMERA 3h/semana).   ║"
echo "║  MAS CUSTA US$ 320+ POR MÊS se ESQUECER LIGADA 24/7 (DESTRUIR NO FINAL!).   ║"
echo "║                                                                              ║"
echo "║  ${BOLD}${YELLOW}ANTES DE FECHAR O LAPTOP / TERMINAR SESSÃO DE ESTUDO:${NC}${BOLD}${RED}                      ║"
echo "║                                                                              ║"
echo "║            ${BOLD}${YELLOW}RODE:  ./destroy.sh${NC}${BOLD}${RED}   (e confirme com DESTROY-TOGGLE-MASTER)        ║"
echo "║                                                                              ║"
echo "║  DEIXAR RDS + EKS + NAT + REDIS ligados 1 semana sem uso = PREJUÍZO 💸        ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo ""
read -r -p "==> Plan concluído. Aplicar TODOS recursos acima na AWS (128432678106)? (sim/NÃO) " resposta
if [[ "$resposta" != "sim" && "$resposta" != "SIM" && "$resposta" != "s" && "$resposta" != "S" ]]; then
  echo "Apply cancelado. Removendo arquivo tfplan.binary."
  rm -f tfplan.binary tfplan.json
  exit 0
fi

echo "==> [4/4] terraform apply tfplan.binary"
echo -e "${YELLOW}⏱️  Tempo estimado: 25 a 35 minutos (majoritariamente provisionamento assíncrono RDS/Redis)...${NC}"
terraform apply -input=false tfplan.binary

rm -f tfplan.binary
echo ""
echo -e "${BOLD}✅ Apply concluído. Consulte outputs com:  terraform output${NC}"
echo ""
echo -e "${BOLD}${YELLOW}📌 OBSERVAÇÃO SOBRE ECR (REPOSITÓRIOS DOCKER):${NC}"
echo -e "  Os 5 repositórios ECR (toggle-master-*-service) são RE-CRIADOS VAZIOS agora."
echo -e "  ${BOLD}${YELLOW}Antes de Deployar no EKS (Sprint 2):${NC}"
echo -e "    • Build local + Docker login no ECR + Tag das 5 imagens + Docker push."
echo -e "    • Script automatizado (criaremos na Sprint 2): push-all-images-to-ecr.sh"
echo ""
echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════════╗"
echo -e "║  ${YELLOW}LEMBRETE DE NOVO (último aviso!)${RED}                            ║"
echo -e "║  FIM DO DIA? RODE:  ${YELLOW}./destroy.sh${RED}                           ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"

