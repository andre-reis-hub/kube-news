# Terraform Setup — api-gateway

## Versões

| Componente       | Versão      | Fonte                                         |
|------------------|-------------|-----------------------------------------------|
| Terraform CLI    | = 1.12.0    | checkpoint-api.hashicorp.com                  |
| AWS Provider     | = 5.98.0    | registry.terraform.io/providers/hashicorp/aws |

## Estrutura gerada

```
api-gateway/
├── modules/
│   └── README.md
├── environments/
│   ├── dev/
│   │   ├── versions.tf
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── staging/
│       ├── versions.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── .terraform-version
├── .gitignore
└── TERRAFORM_SETUP.md
```

## Ambientes

- **dev** — ambiente de desenvolvimento, ideal para testes e iterações rápidas
- **staging** — ambiente de homologação, espelho do ambiente de produção para validação final

## Primeiros passos

1. Entre no ambiente desejado: `cd api-gateway/environments/dev`
2. Copie o arquivo de variáveis: `cp terraform.tfvars.example terraform.tfvars`
3. Edite `terraform.tfvars` com os valores reais
4. Configure as credenciais AWS (`aws configure` ou variáveis de ambiente)
5. Inicialize: `terraform init`
6. Revise o plano: `terraform plan`
7. Aplique: `terraform apply`

## Backend

Backend não configurado — o estado ficará local (`.tfstate`). Para uso em time, configure um backend remoto (recomendado: S3 + DynamoDB para AWS).

## Atualização de versões

As versões estão fixadas com `=` para garantir builds reproduzíveis. Para atualizar:
1. Verifique a nova versão em registry.terraform.io / releases.hashicorp.com
2. Atualize `versions.tf` e `.terraform-version` em todos os ambientes
3. Execute `terraform init -upgrade` em cada ambiente
4. Valide com `terraform plan` antes de aplicar

Considere usar [Renovate](https://docs.renovatebot.com/) ou Dependabot para automatizar PRs de atualização.

## Módulos

Coloque módulos reutilizáveis em `modules/<nome-modulo>/`. Cada módulo deve ter seu próprio `main.tf`, `variables.tf` e `outputs.tf`.
