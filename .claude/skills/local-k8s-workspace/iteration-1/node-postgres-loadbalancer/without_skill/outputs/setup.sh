#!/usr/bin/env bash
# =============================================================================
# setup.sh — Deploy kube-news on a local kind cluster with MetalLB LoadBalancer
# =============================================================================
# Requirements:
#   - docker
#   - kind  (https://kind.sigs.k8s.io/)
#   - kubectl
#   - helm  (for MetalLB installation)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_NAME="kube-news"
APP_IMAGE="kube-news:latest"
MANIFESTS_DIR="$(cd "$(dirname "$0")/k8s" && pwd)"
METALLB_VERSION="0.14.5"
METALLB_NAMESPACE="metallb-system"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || err "'$1' not found. Please install it first."
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
log "Checking required tools..."
require_cmd docker
require_cmd kind
require_cmd kubectl
require_cmd helm

# ---------------------------------------------------------------------------
# Step 1 — Create kind cluster (if it doesn't already exist)
# ---------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  warn "kind cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  log "Creating kind cluster '${CLUSTER_NAME}'..."
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF
fi

# Set kubectl context
kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null \
  || err "Failed to connect to kind cluster '${CLUSTER_NAME}'."
log "kubectl context set to kind-${CLUSTER_NAME}."

# ---------------------------------------------------------------------------
# Step 2 — Build the Docker image and load it into kind
# ---------------------------------------------------------------------------
log "Building Docker image '${APP_IMAGE}'..."
# Build from the project root (two levels up from this script's k8s/ dir,
# or adjust the build context path as needed for your project layout).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/Dockerfile" ]]; then
  docker build -t "${APP_IMAGE}" "${PROJECT_ROOT}"
else
  warn "Dockerfile not found at ${PROJECT_ROOT}/Dockerfile."
  warn "Skipping image build. Make sure '${APP_IMAGE}' is already available locally."
fi

log "Loading image '${APP_IMAGE}' into kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "${APP_IMAGE}" --name "${CLUSTER_NAME}"

# ---------------------------------------------------------------------------
# Step 3 — Install MetalLB via Helm
# ---------------------------------------------------------------------------
log "Adding MetalLB Helm repo..."
helm repo add metallb https://metallb.github.io/metallb --force-update
helm repo update

if helm status metallb -n "${METALLB_NAMESPACE}" &>/dev/null; then
  warn "MetalLB already installed. Skipping Helm install."
else
  log "Installing MetalLB v${METALLB_VERSION}..."
  helm install metallb metallb/metallb \
    --namespace "${METALLB_NAMESPACE}" \
    --create-namespace \
    --version "${METALLB_VERSION}" \
    --wait \
    --timeout 120s
fi

# ---------------------------------------------------------------------------
# Step 4 — Detect Docker network CIDR and patch MetalLB config
# ---------------------------------------------------------------------------
log "Detecting Docker network CIDR for kind cluster..."
KIND_NETWORK="kind"
DOCKER_SUBNET=$(docker network inspect "${KIND_NETWORK}" \
  --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null | head -n1)

if [[ -z "${DOCKER_SUBNET}" ]]; then
  warn "Could not detect kind Docker network subnet. Using default 172.18.255.200-172.18.255.250."
  METALLB_IP_RANGE="172.18.255.200-172.18.255.250"
else
  # Derive a pool from the last /24 block of the subnet
  # e.g. 172.18.0.0/16 -> 172.18.255.200-172.18.255.250
  BASE_IP=$(echo "${DOCKER_SUBNET}" | cut -d'/' -f1)           # e.g. 172.18.0.0
  OCTET1=$(echo "${BASE_IP}" | cut -d'.' -f1)
  OCTET2=$(echo "${BASE_IP}" | cut -d'.' -f2)
  METALLB_IP_RANGE="${OCTET1}.${OCTET2}.255.200-${OCTET1}.${OCTET2}.255.250"
  log "Detected subnet ${DOCKER_SUBNET} -> MetalLB pool: ${METALLB_IP_RANGE}"
fi

# Patch the metallb-config.yaml with the detected range
METALLB_CONFIG="${MANIFESTS_DIR}/metallb-config.yaml"
sed -i "s|172\.18\.255\.200-172\.18\.255\.250|${METALLB_IP_RANGE}|g" "${METALLB_CONFIG}"

# ---------------------------------------------------------------------------
# Step 5 — Wait for MetalLB controller to be ready, then apply its config
# ---------------------------------------------------------------------------
log "Waiting for MetalLB controller to be ready..."
kubectl rollout status deployment/metallb-controller \
  -n "${METALLB_NAMESPACE}" --timeout=120s

log "Waiting for MetalLB webhook to be available..."
# Give the webhook a few extra seconds to register CRDs
kubectl wait --for=condition=available deployment/metallb-controller \
  -n "${METALLB_NAMESPACE}" --timeout=120s

log "Applying MetalLB IPAddressPool and L2Advertisement..."
kubectl apply -f "${METALLB_CONFIG}"

# ---------------------------------------------------------------------------
# Step 6 — Apply application manifests
# ---------------------------------------------------------------------------
log "Applying Kubernetes manifests..."

# Apply in dependency order
kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"
kubectl apply -f "${MANIFESTS_DIR}/postgres-secret.yaml"
kubectl apply -f "${MANIFESTS_DIR}/app-secret.yaml"
kubectl apply -f "${MANIFESTS_DIR}/app-configmap.yaml"
kubectl apply -f "${MANIFESTS_DIR}/postgres-pvc.yaml"
kubectl apply -f "${MANIFESTS_DIR}/postgres-deployment.yaml"
kubectl apply -f "${MANIFESTS_DIR}/postgres-service.yaml"
kubectl apply -f "${MANIFESTS_DIR}/app-deployment.yaml"
kubectl apply -f "${MANIFESTS_DIR}/app-service.yaml"

# ---------------------------------------------------------------------------
# Step 7 — Wait for PostgreSQL to be ready
# ---------------------------------------------------------------------------
log "Waiting for PostgreSQL deployment to be ready..."
kubectl rollout status deployment/postgres \
  -n kube-news --timeout=120s

# ---------------------------------------------------------------------------
# Step 8 — Wait for the app to be ready
# ---------------------------------------------------------------------------
log "Waiting for kube-news app deployment to be ready..."
kubectl rollout status deployment/kube-news \
  -n kube-news --timeout=180s

# ---------------------------------------------------------------------------
# Step 9 — Retrieve the LoadBalancer external IP
# ---------------------------------------------------------------------------
log "Waiting for LoadBalancer external IP to be assigned..."
EXTERNAL_IP=""
RETRIES=30
for i in $(seq 1 ${RETRIES}); do
  EXTERNAL_IP=$(kubectl get svc kube-news -n kube-news \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${EXTERNAL_IP}" ]]; then
    break
  fi
  log "  Attempt ${i}/${RETRIES}: waiting for IP..."
  sleep 5
done

# ---------------------------------------------------------------------------
# Step 10 — Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  kube-news deployed successfully on kind!"
echo "============================================================"
if [[ -n "${EXTERNAL_IP}" ]]; then
  echo "  App URL:       http://${EXTERNAL_IP}"
  echo "  Health check:  http://${EXTERNAL_IP}/health"
  echo "  Ready check:   http://${EXTERNAL_IP}/ready"
  echo "  Metrics:       http://${EXTERNAL_IP}/metrics"
else
  warn "LoadBalancer IP not yet assigned. Run:"
  echo "  kubectl get svc kube-news -n kube-news"
fi
echo ""
echo "  Useful commands:"
echo "    kubectl get all -n kube-news"
echo "    kubectl logs -l app=kube-news -n kube-news -f"
echo "    kubectl logs -l app=postgres  -n kube-news -f"
echo "============================================================"
