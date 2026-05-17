## ADDED Requirements

### Requirement: IAM Role com IRSA para o Cluster Autoscaler
O Terraform SHALL criar uma IAM Role vinculada ao OIDC provider do EKS, com política mínima de autoscaling (DescribeAutoScalingGroups, SetDesiredCapacity, TerminateInstanceInAutoScalingGroup, DescribeLaunchTemplateVersions). A Role SHALL ser anotada no ServiceAccount do Cluster Autoscaler via `eks.amazonaws.com/role-arn`.

#### Scenario: Role criada com trust policy OIDC correta
- **WHEN** `terraform apply` é executado com sucesso
- **THEN** existe uma IAM Role com trust relationship referenciando o OIDC issuer URL do cluster EKS e o ServiceAccount `cluster-autoscaler` no namespace `kube-system`

#### Scenario: ServiceAccount anotado com ARN da Role
- **WHEN** o Helm release é instalado
- **THEN** o ServiceAccount `cluster-autoscaler` em `kube-system` contém a anotação `eks.amazonaws.com/role-arn` com o ARN da Role criada pelo Terraform

---

### Requirement: Tags de autodiscovery no node group
O Terraform SHALL adicionar as tags `k8s.io/cluster-autoscaler/enabled = "true"` e `k8s.io/cluster-autoscaler/<cluster-name> = "owned"` no Managed Node Group do EKS para que o Cluster Autoscaler descubra o ASG automaticamente.

#### Scenario: Tags presentes no node group após apply
- **WHEN** `terraform apply` é executado
- **THEN** o Managed Node Group possui as duas tags de autodiscovery com os valores corretos

#### Scenario: Cluster Autoscaler descobre o ASG
- **WHEN** o pod do Cluster Autoscaler inicia
- **THEN** os logs do pod mostram que o ASG foi descoberto via autodiscovery (sem erros de `no NodeGroups found`)

---

### Requirement: Helm release do Cluster Autoscaler instalado via Terraform
O Terraform SHALL instalar o chart `autoscaler/cluster-autoscaler` via `helm_release` no namespace `kube-system`, configurado com o nome do cluster e a região AWS. O release SHALL depender explicitamente do módulo EKS.

#### Scenario: Pod do Cluster Autoscaler em Running
- **WHEN** `terraform apply` completa com sucesso
- **THEN** `kubectl get pods -n kube-system | grep cluster-autoscaler` retorna um pod com status `Running`

#### Scenario: Terraform destroy remove o Helm release
- **WHEN** `terraform destroy` é executado
- **THEN** o Helm release é removido e nenhum pod do Cluster Autoscaler permanece no cluster

---

### Requirement: Escala automática de nodes baseada em pods Pending
O Cluster Autoscaler SHALL monitorar pods em estado `Pending` por falta de recursos e expandir o ASG adicionando nodes (até `node_max_size`). Nodes subutilizados SHALL ser removidos após o período de cooldown (padrão: 10 minutos), respeitando o mínimo de `node_min_size`.

#### Scenario: Scale-up quando há pods Pending por falta de recursos
- **WHEN** um Deployment é criado com requisição de recursos que excede a capacidade do node atual
- **THEN** o Cluster Autoscaler adiciona um novo node dentro de 3 minutos e os pods transitam para `Running`

#### Scenario: Scale-down de node ocioso
- **WHEN** um node está subutilizado por mais de 10 minutos e seus pods podem ser reagendados em outros nodes
- **THEN** o Cluster Autoscaler remove o node e o número de nodes cai para `node_min_size` (mínimo 1)

#### Scenario: Número de nodes respeita limites configurados
- **WHEN** a demanda de pods é alta
- **THEN** o número de nodes nunca excede `node_max_size` (3)
- **WHEN** o cluster está ocioso
- **THEN** o número de nodes nunca cai abaixo de `node_min_size` (1)
