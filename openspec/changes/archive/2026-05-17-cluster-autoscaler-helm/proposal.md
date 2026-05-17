## Why

O cluster EKS do kube-news usa um único node `t3.small` com tamanho fixo, o que exige intervenção manual via `terraform apply` para escalar. O Cluster Autoscaler elimina essa fricção ao ajustar automaticamente o número de nodes baseado na demanda real dos pods — reduzindo custo quando o cluster está ocioso e adicionando capacidade quando há pods `Pending` por falta de recursos.

## What Changes

- Instalar o **Cluster Autoscaler** via Helm no namespace `kube-system`
- Criar **IAM Role** com política de autoscaling para o node group do EKS (usando IRSA)
- Configurar **ServiceAccount** com anotação IRSA para o Cluster Autoscaler
- Adicionar **tags de autodiscovery** no node group para que o Cluster Autoscaler localize os ASGs gerenciados
- Atualizar `node_min_size`, `node_max_size` e `node_desired_size` no Terraform para suportar escala entre 1 e 3 nodes

## Capabilities

### New Capabilities

- `cluster-autoscaler`: Instalação e configuração do Cluster Autoscaler via Helm com IRSA, incluindo IAM Role, ServiceAccount e tags de autodiscovery no node group

### Modified Capabilities

<!-- Nenhuma capability existente tem seus requisitos alterados -->

## Impact

- **Terraform** (`infra/`): novos recursos IAM, tags no node group, variáveis de escala
- **Helm**: novo release `cluster-autoscaler` no namespace `kube-system`
- **Custo**: nodes ociosos podem ser removidos automaticamente; picos de carga adicionam nodes temporariamente
- **Dependências**: requer OIDC provider habilitado no EKS (já configurado pelo módulo eks.tf)
