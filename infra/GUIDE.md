# Guia de Infraestrutura — kube-news no EKS

Este guia explica cada decisão de arquitetura, como usar o projeto e os comandos do dia a dia.

---

## O que foi criado

O Terraform provisiona toda a infraestrutura necessária para rodar o kube-news na AWS usando EKS (Elastic Kubernetes Service). A infraestrutura segue boas práticas de segurança: os nodes ficam em subnets privadas e nunca ficam expostos diretamente à internet.

```
                          INTERNET
                              │
                    ┌─────────▼──────────┐
                    │  Internet Gateway  │
                    └─────────┬──────────┘
                              │
           ┌──────────────────┼──────────────────┐
           │                  │                  │
  ┌────────▼────────┐ ┌───────▼────────┐ ┌───────▼────────┐
  │  Subnet Pública │ │ Subnet Pública │ │ Subnet Pública │
  │   us-east-1a   │ │  us-east-1b   │ │  us-east-1c   │
  │  10.0.0.0/24   │ │ 10.0.1.0/24   │ │ 10.0.2.0/24   │
  └────────┬────────┘ └───────────────┘ └───────────────┘
           │
    ┌──────▼──────┐
    │  NAT Gateway│  ← Único ponto de saída dos nodes para a internet
    └──────┬──────┘
           │
  ┌────────▼────────┐ ┌───────────────┐ ┌───────────────┐
  │ Subnet Privada  │ │Subnet Privada │ │Subnet Privada │
  │  us-east-1a    │ │  us-east-1b   │ │  us-east-1c   │
  │ 10.0.10.0/24   │ │ 10.0.11.0/24  │ │ 10.0.12.0/24  │
  └────────┬────────┘ └───────┬───────┘ └───────┬───────┘
           │                  │                  │
           └──────────────────▼──────────────────┘
                     [EKS Worker Nodes]
                       (t3.small EC2)
                              │
                    ┌─────────▼──────────┐
                    │  EKS Control Plane │
                    │  (gerenciado AWS)  │
                    └────────────────────┘
```

---

## Arquivos e o que cada um faz

### `versions.tf`
Define quais providers o Terraform vai baixar e em que versão.

- **`hashicorp/aws ~> 5.0`** — provider principal para criar recursos na AWS
- **`hashicorp/kubernetes ~> 2.0`** — permite criar recursos K8s via Terraform após o cluster existir
- **Bloco `backend "s3"` (comentado)** — quando descomentado, salva o estado do Terraform em um bucket S3 com lock no DynamoDB. Essencial em times onde mais de uma pessoa aplica o Terraform.

```hcl
# O provider Kubernetes autentica via AWS CLI — não precisa de kubeconfig salvo em disco
provider "kubernetes" {
  exec {
    command = "aws"
    args    = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}
```

---

### `variables.tf`
Todos os parâmetros configuráveis do projeto, com defaults prontos para uso em dev.

| Variável | Default | Por que esse valor |
|----------|---------|-------------------|
| `aws_region` | `us-east-1` | Região com mais serviços disponíveis e menor latência no Brasil |
| `cluster_version` | `1.30` | Versão estável recente do Kubernetes |
| `node_instance_types` | `["t3.small"]` | 2 vCPU, 2 GB RAM — menor tamanho viável para nodes EKS |
| `node_desired_size` | `1` | Um único node para dev/aprendizado (reduz custo) |
| `node_max_size` | `2` | Permite escalar para um segundo node se necessário |
| `node_disk_size` | `20` | GB de disco por node — suficiente para imagens e logs locais |

> **Por que t3.small e não t3.micro?**
> O t3.micro (1 GB RAM) não é viável para nodes Kubernetes: os pods de sistema da AWS (aws-node, coredns, kube-proxy) sozinhos consomem ~500 MB, deixando menos de 500 MB para a aplicação — o node fica em `MemoryPressure` constantemente.

---

### `locals.tf`
Calcula automaticamente as AZs disponíveis na região e os CIDRs das subnets.

```hcl
# Pega as 3 primeiras AZs disponíveis na região (ex: us-east-1a, 1b, 1c)
azs = slice(data.aws_availability_zones.available.names, 0, 3)

# Gera CIDRs para cada subnet a partir do CIDR da VPC
# Subnets públicas:  10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24
# Subnets privadas: 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
```

Isso elimina hardcode de AZs — se mudar a região no `terraform.tfvars`, tudo se adapta automaticamente.

---

### `vpc.tf`
Cria toda a rede: VPC, subnets, roteamento e NAT gateway.

**Por que subnets públicas E privadas?**
- **Subnets públicas** — recebem um IP público e têm rota direta para a internet via Internet Gateway. Usadas para Load Balancers que precisam receber tráfego externo.
- **Subnets privadas** — sem IP público. Nodes ficam aqui, isolados da internet. Acesso de saída vai pelo NAT Gateway.

**Por que `single_nat_gateway = true`?**
- Uma NAT Gateway por AZ custa ~$32/mês cada. Para dev, uma única NAT basta.
- Em produção, `single_nat_gateway = false` garante que se uma AZ cair, as demais ainda têm saída para internet.

**Tags obrigatórias para o EKS:**
```hcl
# Diz ao EKS quais subnets usar para criar Load Balancers externos
"kubernetes.io/role/elb" = 1  # subnets públicas

# Diz ao EKS quais subnets usar para Load Balancers internos
"kubernetes.io/role/internal-elb" = 1  # subnets privadas
```
Sem essas tags, o EKS não consegue provisionar Load Balancers automaticamente.

---

### `eks.tf`
Cria o cluster EKS e o grupo de nodes gerenciados.

**Control Plane vs. Worker Nodes:**
- O **Control Plane** (API Server, etcd, scheduler, controller-manager) é gerenciado inteiramente pela AWS. Você não acessa, não configura e não paga por EC2 — paga uma taxa fixa de ~$72/mês pelo cluster.
- Os **Worker Nodes** são instâncias EC2 comuns na sua conta, onde os pods da aplicação rodam.

**Managed Node Group:**
O EKS gerencia o ciclo de vida das instâncias EC2: substituição automática de nodes não saudáveis, atualização de versão, autoscaling. Diferente de self-managed nodes, você não precisa gerenciar o `kubelet` manualmente.

**Addons habilitados:**
| Addon | Função |
|-------|--------|
| `vpc-cni` | Atribui IPs da VPC diretamente aos pods (cada pod tem IP real da subnet) |
| `coredns` | DNS interno do cluster — permite pods se encontrarem por nome de serviço |
| `kube-proxy` | Gerencia regras de rede para Services do tipo ClusterIP/NodePort |
| `eks-pod-identity-agent` | Permite pods assumirem IAM Roles sem credenciais hardcoded |

**`enable_cluster_creator_admin_permissions = true`:**
Adiciona automaticamente seu usuário IAM ao ConfigMap `aws-auth` com permissão de admin. Sem isso, mesmo criando o cluster você não consegue executar `kubectl` nele.

---

### `outputs.tf`
Exporta valores úteis após o `terraform apply`.

O output mais importante:
```
configure_kubectl = "aws eks update-kubeconfig --region us-east-1 --name kube-news-eks"
```
Rode esse comando para configurar o `kubectl` apontando para o cluster recém-criado.

---

## Pré-requisitos

1. **Terraform >= 1.5**
   ```bash
   terraform -version
   ```

2. **AWS CLI configurado**
   ```bash
   aws configure
   # Informe: Access Key ID, Secret Access Key, região (us-east-1), formato (json)
   ```

3. **Permissões IAM mínimas necessárias:**
   - `eks:*`
   - `ec2:*` (VPC, subnets, security groups, instâncias)
   - `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole`
   - `elasticloadbalancing:*`

---

## Passo a passo

### 1. Configurar variáveis
```bash
cd infra/
cp terraform.tfvars.example terraform.tfvars
# Edite se necessário (defaults já funcionam para dev)
```

### 2. Inicializar — baixa os providers e módulos
```bash
terraform init
```

### 3. Ver o que será criado (sem aplicar nada)
```bash
terraform plan
```
O plano mostra ~50 recursos: VPC, subnets, route tables, NAT gateway, cluster EKS, node group, IAM roles, security groups, etc.

### 4. Criar a infraestrutura
```bash
terraform apply
# Digite "yes" quando solicitado
# Aguarde ~15 minutos
```

### 5. Configurar o kubectl
```bash
# Copie o comando do output "configure_kubectl":
aws eks update-kubeconfig --region us-east-1 --name kube-news-eks

# Verificar se está funcionando:
kubectl get nodes
kubectl get pods -A
```

### 6. Deploy do kube-news
```bash
# Os manifests em k8s/ precisam de ajuste para usar uma imagem no ECR
# Por enquanto, aplique os manifests (ajuste a imagem conforme necessário):
kubectl apply -f ../k8s/
kubectl get pods
kubectl get svc
```

---

## Operações do dia a dia

### Escalar o cluster manualmente
```bash
# Edite terraform.tfvars:
node_desired_size = 2

terraform apply
```

### Ver logs dos nodes
```bash
kubectl get nodes
kubectl describe node <nome-do-node>
```

### Acessar um pod
```bash
kubectl exec -it <nome-do-pod> -- /bin/sh
```

### Ver uso de recursos
```bash
kubectl top nodes
kubectl top pods
```

### Atualizar a versão do Kubernetes
```bash
# Edite terraform.tfvars:
cluster_version = "1.31"

terraform apply
# O EKS atualiza o Control Plane primeiro, depois os nodes gradualmente
```

---

## Destruir o ambiente (evitar custos)

```bash
terraform destroy
# Digite "yes"
# Aguarde ~10 minutos
```

> Sempre destrua o ambiente quando não estiver usando. O cluster EKS cobra ~$72/mês mesmo sem nenhum pod rodando.

---

## Custos estimados (us-east-1)

| Recurso | Especificação | Custo/mês |
|---------|--------------|-----------|
| EKS Control Plane | Gerenciado pela AWS | ~$72 |
| 1x t3.small node | 2 vCPU, 2 GB RAM | ~$15 |
| NAT Gateway | 1 por VPC | ~$32 |
| EBS (disco do node) | 20 GB gp2 | ~$2 |
| **Total** | | **~$121** |

**Comparação com o que foi reduzido:**
- Antes: 2x t3.medium = ~$60/mês em EC2
- Agora: 1x t3.small = ~$15/mês em EC2
- **Economia: ~$45/mês nos nodes**

---

## Próximos passos sugeridos

1. **Backend remoto** — descomente o bloco `backend "s3"` em `versions.tf` para salvar o state na AWS, permitindo trabalho em time
2. **ECR** — adicionar um módulo `ecr.tf` para criar o repositório de imagens Docker na AWS
3. **Cluster Autoscaler** — instalar via Helm para escalar nodes automaticamente baseado na demanda de pods
4. **AWS Load Balancer Controller** — substitui o `in-tree` controller do EKS para provisionar ALBs modernos via Ingress
5. **IRSA (IAM Roles for Service Accounts)** — usar o OIDC já configurado para dar permissões IAM específicas por pod, sem credenciais hardcoded
