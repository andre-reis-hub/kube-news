## Context

O cluster EKS do kube-news é provisionado via Terraform com um Managed Node Group de tamanho fixo (1 node `t3.small`). O OIDC provider do EKS já está habilitado pelo módulo `terraform-aws-modules/eks`, o que permite usar IRSA (IAM Roles for Service Accounts) sem armazenar credenciais AWS nos pods.

O Cluster Autoscaler é o componente padrão do Kubernetes para escala automática de nodes. Ele monitora pods em estado `Pending` por falta de recursos e expande o Auto Scaling Group (ASG) correspondente, e remove nodes subutilizados após um período configurável.

## Goals / Non-Goals

**Goals:**
- Instalar o Cluster Autoscaler via Helm (chart oficial `autoscaler/cluster-autoscaler`)
- Usar IRSA para autenticação — sem credenciais estáticas no pod
- Configurar autodiscovery via tags no ASG do node group
- Escala entre 1 e 3 nodes `t3.small`
- Toda a infraestrutura IAM provisionada via Terraform

**Non-Goals:**
- Horizontal Pod Autoscaler (HPA) — escala pods, não nodes; fora do escopo
- Karpenter — alternativa mais moderna ao Cluster Autoscaler; pode ser avaliada no futuro
- Métricas customizadas de autoscaling — usar apenas CPU/memória (padrão)

## Decisions

### D1: IRSA em vez de `node_role` com `ec2:*`

**Escolhido**: IAM Role específica para o ServiceAccount do Cluster Autoscaler via OIDC.

**Alternativa descartada**: Adicionar políticas de autoscaling à IAM Role dos nodes EC2. Isso daria permissão de autoscaling a todos os processos no node, violando o princípio do menor privilégio.

**Rationale**: IRSA limita as permissões ao pod do Cluster Autoscaler. Se o pod for comprometido, o raio de explosão fica contido.

---

### D2: Autodiscovery em vez de ASG name explícito

**Escolhido**: Tags `k8s.io/cluster-autoscaler/enabled` e `k8s.io/cluster-autoscaler/<cluster-name>` no node group para autodiscovery.

**Alternativa descartada**: Passar o nome do ASG explicitamente via `--nodes` no Helm values. Isso acopla o Helm release ao nome gerado pelo Terraform (não estável entre recreates).

**Rationale**: Autodiscovery é resiliente a mudanças de nome do ASG e é o modo recomendado pelo projeto.

---

### D3: Helm via Terraform (`helm_release`) em vez de `kubectl apply`

**Escolhido**: Usar o provider `hashicorp/helm` dentro do Terraform para instalar o chart.

**Alternativa descartada**: Script bash separado com `helm install`. Isso cria estado fora do Terraform, dificultando `terraform destroy` completo.

**Rationale**: Tudo em um único `terraform apply`/`destroy` — infraestrutura e aplicação do autoscaler juntas.

---

### D4: Arquivo `helm.tf` separado

**Escolhido**: Criar `infra/helm.tf` para o Helm release do Cluster Autoscaler.

**Rationale**: Separa preocupações — `eks.tf` gerencia o cluster, `helm.tf` gerencia workloads de infraestrutura instalados via Helm.

## Risks / Trade-offs

- **[Risco] Versão do chart vs. versão do K8s** → Verificar compatibilidade: o chart autoscaler `9.x` suporta K8s 1.30. Fixar a versão do chart no `helm_release` para evitar atualizações acidentais.
- **[Risco] Race condition no `terraform apply`** → O `helm_release` depende do cluster estar pronto. Adicionar `depends_on = [module.eks]` explicitamente.
- **[Trade-off] Node único pode ser removido** → Com `scale-down-enabled = true` e apenas 1 node, o autoscaler pode tentar removê-lo se subutilizado. Configurar `min_size = 1` no node group garante que sempre haverá ao menos 1 node.
- **[Risco] Tempo de scale-up (~2 min)** → Provisionar um novo EC2 demora ~2 minutos. Picos súbitos de carga podem ter degradação transitória. Aceitável para o contexto de aprendizado.

## Migration Plan

1. Adicionar provider `helm` em `versions.tf`
2. Criar `infra/autoscaler-iam.tf` com IAM Role + Policy IRSA
3. Adicionar tags de autodiscovery no node group em `infra/eks.tf`
4. Criar `infra/helm.tf` com o `helm_release` do Cluster Autoscaler
5. Atualizar `infra/variables.tf` com `node_min_size`
6. Atualizar `infra/outputs.tf` com output do Helm release
7. Rodar `terraform init` (novo provider helm) + `terraform apply`
8. Verificar: `kubectl get pods -n kube-system | grep cluster-autoscaler`
9. Rollback: `terraform destroy -target=helm_release.cluster_autoscaler` remove o Helm release sem destruir o cluster

## Open Questions

- Nenhuma questão bloqueante identificada.
