# kube-news — Infraestrutura (Terraform + EKS)

Provisiona um cluster EKS na AWS com VPC multi-AZ, subnets privadas/públicas, NAT gateway e autoscaling de nodes.

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configurado (`aws configure`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- Permissões IAM suficientes (EKS, EC2, VPC, IAM)

## Estrutura

```
infra/
├── versions.tf              # Providers e versões
├── variables.tf             # Variáveis de entrada
├── locals.tf                # Cálculo de AZs e CIDRs
├── vpc.tf                   # VPC, subnets, NAT gateway
├── eks.tf                   # Cluster EKS + managed node group
├── outputs.tf               # Outputs úteis (endpoint, kubeconfig cmd)
└── terraform.tfvars.example # Exemplo de valores
```

## Arquitetura

```
                        Internet
                           │
                     [IGW - Internet Gateway]
                           │
              ┌────────────┼────────────┐
              │            │            │
         [Public]     [Public]     [Public]
          us-east-1a  us-east-1b  us-east-1c
              │
          [NAT GW]
              │
    ┌─────────┼─────────┐
    │         │         │
[Private] [Private] [Private]
  1a        1b        1c
    │         │         │
    └────[EKS Nodes]────┘
              │
        [EKS Control Plane]
        (gerenciado pela AWS)
```

## Como usar

### 1. Configurar variáveis

```bash
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com seus valores
```

### 2. Inicializar

```bash
terraform init
```

### 3. Planejar

```bash
terraform plan
```

### 4. Aplicar

```bash
terraform apply
```

A criação do cluster leva ~15 minutos.

### 5. Configurar kubectl

```bash
# O comando exato aparece no output após o apply:
aws eks update-kubeconfig --region us-east-1 --name kube-news-eks

# Verificar nodes:
kubectl get nodes
```

### 6. Destruir (evitar custos)

```bash
terraform destroy
```

## Deploy do kube-news no cluster

Após o cluster estar pronto, faça o push da imagem para o ECR e aplique os manifests:

```bash
# Build e push para ECR (substitua <account-id> e <region>)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

docker build -t kube-news ../
docker tag kube-news:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/kube-news:latest
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/kube-news:latest

# Aplicar manifests K8s (ajustar imagePullPolicy e image no app-deployment.yaml)
kubectl apply -f ../k8s/
```

## Custos estimados (us-east-1, dev)

| Recurso | Custo/mês (aprox.) |
|---------|-------------------|
| EKS Control Plane | ~$72 |
| 2x t3.medium nodes | ~$60 |
| NAT Gateway | ~$32 |
| **Total** | **~$164** |

> Dica: use `terraform destroy` quando não estiver usando para evitar custos.
