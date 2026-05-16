#!/usr/bin/env bash
# setup.sh — Automates the full local Kubernetes environment for Flask + Redis
# Prerequisites: kind, kubectl, docker

set -euo pipefail

CLUSTER_NAME="flask-redis-cluster"
IMAGE_NAME="flask-redis-web:latest"
NAMESPACE="flask-redis"
METALLB_VERSION="v0.14.4"

# --------------------------------------------------------------------------- #
# Helper functions
# --------------------------------------------------------------------------- #
log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require() {
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || die "'$cmd' is not installed or not on PATH."
  done
}

# --------------------------------------------------------------------------- #
# 1. Pre-flight checks
# --------------------------------------------------------------------------- #
log "Checking required tools..."
require kind kubectl docker

# --------------------------------------------------------------------------- #
# 2. Create kind cluster (with extraPortMappings for local access fallback)
# --------------------------------------------------------------------------- #
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
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

kubectl config use-context "kind-${CLUSTER_NAME}"

# --------------------------------------------------------------------------- #
# 3. Build the Docker image and load it into kind
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/Dockerfile" ]]; then
  log "Building Docker image '${IMAGE_NAME}'..."
  docker build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"
else
  warn "No Dockerfile found at ${SCRIPT_DIR}. Skipping image build."
  warn "Make sure '${IMAGE_NAME}' exists locally before continuing."
fi

log "Loading image '${IMAGE_NAME}' into kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "${IMAGE_NAME}" --name "${CLUSTER_NAME}"

# --------------------------------------------------------------------------- #
# 4. Install MetalLB (LoadBalancer support for kind)
# --------------------------------------------------------------------------- #
log "Installing MetalLB ${METALLB_VERSION}..."
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

log "Waiting for MetalLB controller to be ready..."
kubectl wait deployment -n metallb-system controller \
  --for=condition=Available \
  --timeout=120s

log "Waiting for MetalLB speaker DaemonSet..."
kubectl rollout status daemonset/speaker -n metallb-system --timeout=120s

# Discover the Docker network CIDR used by kind
DOCKER_NETWORK=$(docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' kind 2>/dev/null || echo "")
if [[ -z "${DOCKER_NETWORK}" ]]; then
  die "Could not detect kind Docker network. Is the cluster running?"
fi

# Derive a /28 address pool from the kind network (last .200–.210 block)
BASE_IP=$(echo "${DOCKER_NETWORK}" | cut -d'.' -f1-3)
POOL_START="${BASE_IP}.200"
POOL_END="${BASE_IP}.210"

log "Configuring MetalLB IP pool: ${POOL_START} - ${POOL_END}"
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - ${POOL_START}-${POOL_END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
EOF

# --------------------------------------------------------------------------- #
# 5. Apply Kubernetes manifests
# --------------------------------------------------------------------------- #
K8S_DIR="${SCRIPT_DIR}/k8s"

log "Applying Kubernetes manifests from ${K8S_DIR}..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/redis-deployment.yaml"
kubectl apply -f "${K8S_DIR}/redis-service.yaml"
kubectl apply -f "${K8S_DIR}/web-configmap.yaml"
kubectl apply -f "${K8S_DIR}/web-deployment.yaml"
kubectl apply -f "${K8S_DIR}/web-service.yaml"

# --------------------------------------------------------------------------- #
# 6. Wait for deployments to be ready
# --------------------------------------------------------------------------- #
log "Waiting for Redis deployment..."
kubectl wait deployment/redis -n "${NAMESPACE}" \
  --for=condition=Available \
  --timeout=120s

log "Waiting for web deployment..."
kubectl wait deployment/web -n "${NAMESPACE}" \
  --for=condition=Available \
  --timeout=120s

# --------------------------------------------------------------------------- #
# 7. Retrieve the external IP and test /ping
# --------------------------------------------------------------------------- #
log "Fetching LoadBalancer external IP..."
EXTERNAL_IP=""
RETRIES=30
for i in $(seq 1 ${RETRIES}); do
  EXTERNAL_IP=$(kubectl get svc web -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "${EXTERNAL_IP}" ]] && break
  log "Waiting for external IP... (${i}/${RETRIES})"
  sleep 5
done

if [[ -z "${EXTERNAL_IP}" ]]; then
  warn "LoadBalancer IP not assigned after ${RETRIES} attempts."
  warn "Check: kubectl get svc web -n ${NAMESPACE}"
else
  log "Application is available at: http://${EXTERNAL_IP}/ping"

  log "Testing /ping endpoint..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${EXTERNAL_IP}/ping" || true)
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    log "Health check PASSED — /ping returned HTTP 200."
  else
    warn "Health check returned HTTP ${HTTP_STATUS}. The app may still be starting."
  fi
fi

# --------------------------------------------------------------------------- #
# 8. Summary
# --------------------------------------------------------------------------- #
echo ""
echo "=========================================="
echo " Deployment complete!"
echo "=========================================="
echo " Cluster  : ${CLUSTER_NAME}"
echo " Namespace: ${NAMESPACE}"
echo " App URL  : http://${EXTERNAL_IP:-<pending>}"
echo ""
echo " Useful commands:"
echo "   kubectl get all -n ${NAMESPACE}"
echo "   kubectl logs -l app=web -n ${NAMESPACE} --tail=50"
echo "   kubectl logs -l app=redis -n ${NAMESPACE} --tail=50"
echo ""
echo " To delete the cluster:"
echo "   kind delete cluster --name ${CLUSTER_NAME}"
echo "=========================================="
