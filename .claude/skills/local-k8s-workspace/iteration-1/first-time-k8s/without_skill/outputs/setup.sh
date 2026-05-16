#!/usr/bin/env bash
# =============================================================================
# setup.sh — Sobe o kube-news em Kubernetes local com kind
# =============================================================================
# Pré-requisitos (instalados antes de rodar este script):
#   - Docker em execução
#   - kind   (https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
#   - kubectl (https://kubernetes.io/docs/tasks/tools/)
#
# Execute da raiz do projeto (onde está o Dockerfile):
#   chmod +x setup.sh
#   ./setup.sh
# =============================================================================

set -euo pipefail

# Diretório raiz do projeto (onde fica o Dockerfile)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../../../../../.." && pwd)"
# Se você rodar este script diretamente da raiz do projeto, use:
# PROJECT_ROOT="$(pwd)"

CLUSTER_NAME="kube-news"
IMAGE_NAME="kube-news:latest"
NAMESPACE="kube-news"
K8S_DIR="${SCRIPT_DIR}/k8s"

echo "========================================"
echo "  kube-news — setup Kubernetes local"
echo "========================================"
echo ""

# ── 1. Verificar dependências ─────────────────────────────────────────────────
echo "[1/6] Verificando dependências..."
for cmd in docker kind kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERRO: '$cmd' não encontrado. Instale e tente novamente."
    exit 1
  fi
done
echo "  OK: docker, kind e kubectl encontrados."
echo ""

# ── 2. Criar o cluster kind ───────────────────────────────────────────────────
echo "[2/6] Criando cluster kind '${CLUSTER_NAME}'..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "  Cluster '${CLUSTER_NAME}' já existe, pulando criação."
else
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${K8S_DIR}/kind-config.yaml"
  echo "  Cluster criado com sucesso."
fi
echo ""

# ── 3. Build da imagem Docker ─────────────────────────────────────────────────
echo "[3/6] Fazendo build da imagem Docker '${IMAGE_NAME}'..."
docker build -t "${IMAGE_NAME}" "${PROJECT_ROOT}"
echo "  Build concluído."
echo ""

# ── 4. Carregar imagem no cluster kind ───────────────────────────────────────
# O kind roda dentro do Docker, então ele não enxerga as imagens locais do seu
# Docker diretamente. O comando abaixo copia a imagem para dentro do cluster.
echo "[4/6] Carregando imagem no cluster kind..."
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"
echo "  Imagem carregada."
echo ""

# ── 5. Aplicar manifests Kubernetes ──────────────────────────────────────────
echo "[5/6] Aplicando manifests Kubernetes..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/postgres-secret.yaml"
kubectl apply -f "${K8S_DIR}/postgres-pvc.yaml"
kubectl apply -f "${K8S_DIR}/postgres-deployment.yaml"
kubectl apply -f "${K8S_DIR}/postgres-service.yaml"
kubectl apply -f "${K8S_DIR}/app-deployment.yaml"
kubectl apply -f "${K8S_DIR}/app-service.yaml"
echo "  Manifests aplicados."
echo ""

# ── 6. Aguardar os pods ficarem prontos ──────────────────────────────────────
echo "[6/6] Aguardando pods ficarem prontos (pode levar ~60 segundos)..."

echo "  Aguardando postgres..."
kubectl rollout status deployment/postgres \
  -n "${NAMESPACE}" \
  --timeout=120s

echo "  Aguardando kube-news..."
kubectl rollout status deployment/kube-news \
  -n "${NAMESPACE}" \
  --timeout=120s

echo ""
echo "========================================"
echo "  Tudo pronto!"
echo "========================================"
echo ""
echo "  Acesse a aplicacao no browser:"
echo "  http://localhost:8080"
echo ""
echo "  Comandos uteis:"
echo "  kubectl get pods -n ${NAMESPACE}          # listar pods"
echo "  kubectl logs -n ${NAMESPACE} deploy/kube-news  # ver logs da app"
echo "  kubectl logs -n ${NAMESPACE} deploy/postgres   # ver logs do banco"
echo ""
echo "  Para destruir tudo:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"
echo ""
