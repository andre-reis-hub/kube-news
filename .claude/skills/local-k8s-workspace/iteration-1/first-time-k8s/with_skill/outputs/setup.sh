#!/bin/bash
set -e

echo "=== [1/6] Criando cluster kind ==="
kind create cluster

echo "=== [2/6] Buildando e carregando imagem no cluster ==="
docker build -t kube-news:latest .
kind load docker-image kube-news:latest

echo "=== [3/6] Instalando MetalLB ==="
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

echo "=== [4/6] Configurando MetalLB com IP pool IPv4 ==="
# kind usa Docker network com subnets IPv4 e IPv6.
# O grep -v ':' garante que pegamos apenas a subnet IPv4.
SUBNET=$(docker network inspect kind \
  -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' \
  | tr ' ' '\n' | grep -v ':' | head -1)
BASE=$(echo "$SUBNET" | cut -d. -f1-2)
START="${BASE}.255.200"
END="${BASE}.255.250"

echo "  -> Usando range de IPs: ${START}-${END}"

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

echo "=== [5/6] Aplicando manifests Kubernetes ==="
kubectl apply -f k8s/

echo "=== [6/6] Aguardando pods ficarem prontos ==="
echo "  -> Aguardando postgres..."
kubectl wait --for=condition=ready pod --selector=app=postgres --timeout=120s

echo "  -> Aguardando kube-news (pode demorar um pouco enquanto o DB inicia)..."
kubectl wait --for=condition=ready pod --selector=app=kube-news --timeout=120s

EXTERNAL_IP=$(kubectl get svc kube-news -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo ""
echo "=================================================="
echo "  Tudo pronto! Acesse no browser:"
echo "  http://${EXTERNAL_IP}"
echo "=================================================="
