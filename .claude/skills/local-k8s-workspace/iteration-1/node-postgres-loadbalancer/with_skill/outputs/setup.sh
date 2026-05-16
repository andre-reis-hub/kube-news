#!/bin/bash
set -e

# -------------------------------------------------------
# Setup script: kube-news local Kubernetes with kind + MetalLB
# -------------------------------------------------------

# Step 1 — Check prerequisites
echo ">>> Checking prerequisites..."

if ! which kind &>/dev/null; then
  echo "kind not found. Installing to ~/.local/bin ..."
  curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
  chmod +x /tmp/kind
  mkdir -p ~/.local/bin
  mv /tmp/kind ~/.local/bin/kind
  echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
  export PATH=$PATH:$HOME/.local/bin
fi

if ! which kubectl &>/dev/null; then
  echo "kubectl not found. Installing to ~/.local/bin ..."
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -Lo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl
  mkdir -p ~/.local/bin
  mv /tmp/kubectl ~/.local/bin/kubectl
  export PATH=$PATH:$HOME/.local/bin
fi

echo "kind: $(kind version)"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

# Step 2 — Create the kind cluster
echo ">>> Creating kind cluster..."
kind create cluster --name kube-news

# Step 3 — Build and load the app image
echo ">>> Building Docker image..."
docker build -t kube-news:latest .

echo ">>> Loading image into kind cluster..."
kind load docker-image kube-news:latest --name kube-news

# Step 4 — Install MetalLB
echo ">>> Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

echo ">>> Waiting for MetalLB pods to be ready..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

# Step 5 — Configure MetalLB IP pool (IPv4 only — kind network may expose IPv6 too)
echo ">>> Configuring MetalLB IP address pool..."

SUBNET=$(docker network inspect kind \
  -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' \
  | tr ' ' '\n' | grep -v ':' | head -1)

BASE=$(echo "$SUBNET" | cut -d. -f1-2)
START="${BASE}.255.200"
END="${BASE}.255.250"

echo "    Using IP range: ${START}-${END}"

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

# Step 6 — Deploy all Kubernetes manifests
echo ">>> Applying Kubernetes manifests..."
kubectl apply -f k8s/

# Step 7 — Wait for pods to be ready
echo ">>> Waiting for postgres to be ready..."
kubectl wait --for=condition=ready pod \
  --selector=app=postgres \
  --timeout=120s

echo ">>> Waiting for kube-news app to be ready..."
kubectl wait --for=condition=ready pod \
  --selector=app=kube-news \
  --timeout=120s

# Step 8 — Report external IP
EXTERNAL_IP=$(kubectl get svc kube-news -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo ""
echo "================================================="
echo " Deployment complete!"
echo " Acesse: http://${EXTERNAL_IP}"
echo "================================================="
echo ""
echo "Useful commands:"
echo "  kubectl get pods"
echo "  kubectl get svc"
echo "  kubectl logs deployment/kube-news"
echo "  kubectl logs deployment/postgres"
