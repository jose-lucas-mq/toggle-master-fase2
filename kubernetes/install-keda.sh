#!/usr/bin/env bash
# =============================================================================
# kubernetes/install-keda.sh
# -----------------------------------------------------------------------------
# Instala os componentes de autoscaling da Sprint 3 no cluster EKS:
#
#   1) Metrics Server  → habilita `kubectl top` e o HPA por CPU (evaluation)
#   2) KEDA            → autoscaling orientado a eventos SQS (analytics)
#
# O KEDA é instalado usando a ServiceAccount `keda-operator` JÁ EXISTENTE no
# namespace `keda` (criada por serviceaccounts.yaml), que está anotada com a
# IAM Role via IRSA (`eks.amazonaws.com/role-arn`). Assim KEDA consegue ler as
# métricas da fila SQS SEM credenciais hardcoded.
#
# PRE-REQUISITOS:
#   - kubectl apontando para o cluster toggle-master-eks
#   - helm instalado
#   - kubernetes/apply.sh já rodou (SA `keda-operator` criada com IRSA)
#
# USO:
#   cd kubernetes && ./install-keda.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Profile AWS que assume a role que criou o cluster EKS (necessario para o kubectl/helm).
export AWS_PROFILE="${AWS_PROFILE:-toggl}"

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}  ToggleMaster — Instalando Metrics Server + KEDA (Sprint 3)   ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"
echo ""

# ----------------------------------------------------------------------------
# 0) Sanidade: kubectl + helm
# ----------------------------------------------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "${RED}ERRO: kubectl nao encontrado no PATH.${NC}"; exit 1
fi
if ! command -v helm >/dev/null 2>&1; then
  echo -e "${RED}ERRO: helm nao encontrado no PATH.${NC}"; exit 1
fi

echo -e "${YELLOW}[0/4] Verificando conexao com o cluster...${NC}"
kubectl cluster-info >/dev/null 2>&1 || {
  echo -e "${RED}ERRO: kubectl nao conecta ao cluster.${NC}"
  echo "Rode: aws eks update-kubeconfig --region us-east-1 --name toggle-master-eks"
  exit 1
}
echo -e "${GREEN}  ✓ Cluster acessivel.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 1) Metrics Server (HPA por CPU)
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[1/4] Instalando Metrics Server...${NC}"
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
  echo -e "${GREEN}  ✓ Metrics Server ja instalado. Pulando.${NC}"
else
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  echo -e "  Aguardando Metrics Server ficar READY..."
  kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
  echo -e "${GREEN}  ✓ Metrics Server pronto.${NC}"
fi
echo ""

# ----------------------------------------------------------------------------
# 2) Namespace keda + ServiceAccount IRSA (garante que exists antes do Helm)
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[2/4] Verificando namespace keda + ServiceAccount com IRSA...${NC}"
kubectl get ns keda >/dev/null 2>&1 || kubectl create namespace keda

if ! kubectl -n keda get sa keda-operator >/dev/null 2>&1; then
  echo -e "${RED}  ERRO: ServiceAccount 'keda-operator' nao existe no namespace keda.${NC}"
  echo -e "  Rode primeiro: ${BLUE}cd kubernetes && ./apply.sh${NC} (aplica serviceaccounts.gen.yaml)"
  exit 1
fi

KEDA_ROLE_ARN=$(kubectl -n keda get sa keda-operator \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)
if [[ -z "$KEDA_ROLE_ARN" ]]; then
  echo -e "${RED}  ERRO: ServiceAccount keda-operator sem anotacao de IRSA.${NC}"
  echo -e "  Verifique se serviceaccounts.gen.yaml foi gerado com {{IRSA_KEDA_ROLE_ARN}}."
  exit 1
fi
echo -e "${GREEN}  ✓ keda-operator anotada com IRSA: ${KEDA_ROLE_ARN}${NC}"
echo ""

# ----------------------------------------------------------------------------
# 3) KEDA via Helm (usando a SA existente, sem criar outra)
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[3/4] Instalando KEDA via Helm...${NC}"
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
helm repo update kedacore >/dev/null 2>&1 || true

# KEDA_CHART_VERSION pode ser fixada (ex.: 2.16.1). Vazio = ultima estavel.
HELM_VERSION_ARGS=()
if [[ -n "${KEDA_CHART_VERSION:-}" ]]; then
  HELM_VERSION_ARGS=(--version "$KEDA_CHART_VERSION")
fi

helm upgrade --install keda kedacore/keda \
  --namespace keda \
  ${HELM_VERSION_ARGS[@]+"${HELM_VERSION_ARGS[@]}"} \
  --set serviceAccount.operator.create=false \
  --set serviceAccount.operator.name=keda-operator \
  --wait --timeout 300s

echo -e "  Aguardando pods do KEDA ficarem READY..."
kubectl -n keda rollout status deployment/keda-operator --timeout=180s
kubectl -n keda rollout status deployment/keda-operator-metrics-apiserver --timeout=180s
echo -e "${GREEN}  ✓ KEDA pronto.${NC}"
echo ""

# ----------------------------------------------------------------------------
# 4) Verificacao final
# ----------------------------------------------------------------------------
echo -e "${YELLOW}[4/4] Verificacao final...${NC}"
echo ""
kubectl -n keda get pods
echo ""
kubectl get apiservice v1beta1.external.metrics.k8s.io >/dev/null 2>&1 \
  && echo -e "${GREEN}  ✓ API de métricas externas do KEDA registrada.${NC}" \
  || echo -e "${YELLOW}  ! API v1beta1.external.metrics.k8s.io ainda nao registrada (aguarde alguns segundos).${NC}"

echo ""
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}  Metrics Server + KEDA instalados!                             ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo ""
echo -e "${YELLOW}Proximos passos:${NC}"
echo "  # Aplicar HPA (evaluation) e ScaledObject (analytics):"
echo "  kubectl apply -f hpa-evaluation.gen.yaml"
echo "  kubectl apply -f keda-scaledobject.gen.yaml"
echo ""
echo "  # Acompanhar:"
echo "  kubectl get hpa -n apps -w"
echo "  kubectl get scaledobject -n apps"
echo "  kubectl get pods -n apps -w"
echo ""
