#!/bin/bash
set -e

echo "==> Criando cluster kind..."
kind create cluster --config k8s/kind-config.yaml

echo ""
echo "==> Buildando imagem Docker..."
docker build -t kube-news:latest .

echo ""
echo "==> Carregando imagem no cluster..."
kind load docker-image kube-news:latest

echo ""
echo "==> Instalando MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

echo "    Aguardando MetalLB ficar pronto..."
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

echo ""
echo "==> Configurando IP pool do MetalLB..."
SUBNET=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' | grep -v ':' | head -1)
BASE=$(echo "$SUBNET" | cut -d. -f1-2)
START="${BASE}.255.200"
END="${BASE}.255.250"

echo "    Subnet detectada: $SUBNET"
echo "    Range MetalLB: $START - $END"

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

echo ""
echo "==> Aplicando manifestos da aplicação..."
ls k8s/*.yaml | grep -v kind-config.yaml | xargs kubectl apply -f

echo ""
echo "==> Aguardando pods ficarem prontos..."
kubectl wait --for=condition=ready pod --selector=app=postgres --timeout=120s
kubectl wait --for=condition=ready pod --selector=app=kube-news --timeout=120s

echo ""
echo "==> Tudo pronto! Detalhes do serviço:"
kubectl get svc kube-news

EXTERNAL_IP=$(kubectl get svc kube-news -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo ""
echo "Acesse (Windows/WSL2): http://localhost:8080"
echo "Acesse (MetalLB IP):   http://${EXTERNAL_IP}"
