#!/bin/bash
set -e

# ─── Check dependencies ────────────────────────────────────────────────────────
for tool in kind kubectl docker; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: '$tool' not found. Please install it before running this script."
    exit 1
  fi
done

# ─── 1. Create kind cluster ────────────────────────────────────────────────────
echo "==> Creating kind cluster..."
kind create cluster --name flask-redis

# ─── 2. Build and load app image ──────────────────────────────────────────────
echo "==> Building Docker image..."
docker build -t web:latest .

echo "==> Loading image into kind cluster..."
kind load docker-image web:latest --name flask-redis

# ─── 3. Install MetalLB ───────────────────────────────────────────────────────
echo "==> Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

echo "==> Waiting for MetalLB pods to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

# ─── 4. Configure MetalLB IP pool (IPv4 only) ─────────────────────────────────
echo "==> Configuring MetalLB IPAddressPool..."
# kind's Docker network may have both IPv4 and IPv6 subnets.
# Filter with grep -v ':' to select IPv4 only.
SUBNET=$(docker network inspect kind \
  -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' \
  | tr ' ' '\n' | grep -v ':' | head -1)
BASE=$(echo "$SUBNET" | cut -d. -f1-2)
START="${BASE}.255.200"
END="${BASE}.255.250"

kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - ${START}-${END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
EOF

# ─── 5. Apply Kubernetes manifests ────────────────────────────────────────────
echo "==> Applying manifests..."
kubectl apply -f k8s/

# ─── 6. Wait for pods to be ready ─────────────────────────────────────────────
echo "==> Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod --selector=app=redis --timeout=120s

echo "==> Waiting for Flask app to be ready..."
kubectl wait --for=condition=ready pod --selector=app=web --timeout=120s

# ─── 7. Report external IP ────────────────────────────────────────────────────
EXTERNAL_IP=$(kubectl get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo ""
echo "Deployment complete!"
echo "Acesse: http://${EXTERNAL_IP}"
echo "Health check: curl http://${EXTERNAL_IP}/ping"
