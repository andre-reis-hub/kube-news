## 1. Terraform — Provider Helm

- [x] 1.1 Adicionar `hashicorp/helm ~> 2.0` ao bloco `required_providers` em `infra/versions.tf`
- [x] 1.2 Configurar o provider `helm` em `infra/versions.tf` usando `exec` com `aws eks get-token` (mesmo padrão do provider kubernetes)

## 2. Terraform — IAM Role IRSA para o Cluster Autoscaler

- [x] 2.1 Criar `infra/autoscaler-iam.tf` com a IAM Policy contendo as permissões mínimas de autoscaling (DescribeAutoScalingGroups, DescribeAutoScalingInstances, DescribeLaunchTemplateVersions, DescribeScalingActivities, SetDesiredCapacity, TerminateInstanceInAutoScalingGroup)
- [x] 2.2 Criar a IAM Role com trust policy referenciando o OIDC provider do EKS (`module.eks.oidc_provider_arn`) e o ServiceAccount `cluster-autoscaler` no namespace `kube-system`
- [x] 2.3 Criar `aws_iam_role_policy_attachment` vinculando a policy à role
- [x] 2.4 Adicionar output `cluster_autoscaler_role_arn` em `infra/outputs.tf`

## 3. Terraform — Tags de Autodiscovery no Node Group

- [x] 3.1 Adicionar as tags `k8s.io/cluster-autoscaler/enabled = "true"` e `k8s.io/cluster-autoscaler/<cluster-name> = "owned"` no bloco `node_group_defaults` ou no managed node group em `infra/eks.tf`

## 4. Terraform — Variáveis de Escala

- [x] 4.1 Adicionar variável `node_min_size` em `infra/variables.tf` com default `1`
- [x] 4.2 Atualizar o node group em `infra/eks.tf` para usar `node_min_size` no campo `min_size`

## 5. Terraform — Helm Release do Cluster Autoscaler

- [x] 5.1 Criar `infra/helm.tf` com `resource "helm_release" "cluster_autoscaler"`
- [x] 5.2 Configurar repositório `https://kubernetes.github.io/autoscaler`, chart `cluster-autoscaler`, versão compatível com K8s 1.30 (ex: `9.37.0`), namespace `kube-system`
- [x] 5.3 Definir `values` com: `autoDiscovery.clusterName`, `awsRegion`, `rbac.serviceAccount.annotations` (com o ARN da IAM Role IRSA), `rbac.serviceAccount.create = true`
- [x] 5.4 Adicionar `depends_on = [module.eks]` no `helm_release`

## 6. Aplicar e Verificar

- [ ] 6.1 Rodar `terraform init` na pasta `infra/` para baixar o provider helm
- [ ] 6.2 Rodar `terraform plan` e revisar os novos recursos (IAM Role, Policy, Helm release)
- [ ] 6.3 Rodar `terraform apply` e aguardar conclusão
- [ ] 6.4 Verificar pod rodando: `kubectl get pods -n kube-system | grep cluster-autoscaler`
- [ ] 6.5 Verificar logs sem erros de autodiscovery: `kubectl logs -n kube-system deployment/cluster-autoscaler-aws-cluster-autoscaler | grep -i "found\|error"`
- [x] 6.6 Atualizar `infra/GUIDE.md` adicionando seção sobre o Cluster Autoscaler
