---
name: gerador-terraform
description: >
  Generates a complete, modular Terraform project scaffold for AWS with best practices applied.
  Use this skill whenever the user wants to create a new Terraform project, scaffold AWS infrastructure,
  set up a Terraform directory structure, or organize a Terraform project with environments and modules.
  Trigger even for casual requests like "cria um projeto terraform", "monta a estrutura do terraform",
  "quero começar um projeto terraform pra AWS", or "gera o scaffold terraform pra mim" — even without
  specifying AWS explicitly, since this project targets AWS. Always fetches the latest Terraform CLI
  and AWS provider versions from official sources before generating any file. Never create files from
  memory — always consult context7 for syntax and best practices first.
---

# Gerador Terraform (AWS)

## O que esta skill faz

Dado um nome de projeto e os ambientes desejados, gera:

1. Estrutura de diretórios modularizável (`modules/` + `environments/<env>/`)
2. Arquivos Terraform com versões exatas e atuais (Terraform CLI + AWS provider)
3. `.gitignore`, `.terraform-version` e `terraform.tfvars.example`
4. Relatório `TERRAFORM_SETUP.md` com versões usadas e próximos passos
5. Executa `terraform fmt -recursive` para garantir formatação padrão

## Passo 1 — Guard: verificar se já existe projeto Terraform

Antes de qualquer coisa, verifique se há arquivos `.tf` no diretório atual:

```bash
find . -maxdepth 3 -name "*.tf" | head -5
```

Se encontrar arquivos `.tf`, **pare aqui** e informe o usuário:

> "Já existe uma estrutura Terraform neste diretório. Esta skill cria projetos do zero para evitar sobrescrever trabalho existente."

## Passo 2 — Coletar informações

Pergunte ao usuário (se não estiverem no prompt):
- **Nome do projeto** (usado como nome do diretório raiz)
- **Quais ambientes** deseja criar (ex: `production`, `staging`, `dev` — sem obrigação de ter todos os três)

## Passo 3 — Buscar versões atuais

Execute as duas buscas em paralelo:

**Versão do Terraform CLI:**
Use WebFetch em `https://checkpoint-api.hashicorp.com/v1/check/terraform`
Extraia o campo `current_version` do JSON retornado.

**Versão do AWS Provider:**
Use WebFetch em `https://registry.terraform.io/v1/providers/hashicorp/aws`
Extraia o campo `version` do JSON retornado (versão mais recente publicada).

Salve ambas as versões — elas serão usadas em **todos** os arquivos gerados.

## Passo 4 — Consultar context7

Faça as duas consultas em paralelo via context7:

1. **Terraform (estrutura e boas práticas):**
   - `resolve-library-id` com `libraryName: "Terraform"` e query sobre estrutura de projetos modulares
   - `query-docs` com foco em: `required_providers`, `terraform {}` block, organização de módulos, `versions.tf`

2. **AWS Provider:**
   - `resolve-library-id` com `libraryName: "Terraform AWS Provider"` e query sobre configuração do provider
   - `query-docs` com foco em: bloco `provider "aws"`, variáveis de região, boas práticas de autenticação

Use a documentação retornada para garantir sintaxe correta nos arquivos gerados. Nunca escreva blocos HCL de memória.

## Passo 5 — Gerar a estrutura

Crie o projeto no diretório atual com a seguinte estrutura:

```
<nome-projeto>/
├── modules/
│   └── README.md
├── environments/
│   └── <env>/               ← um por ambiente informado
│       ├── versions.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── .terraform-version
├── .gitignore
└── TERRAFORM_SETUP.md
```

### versions.tf (em cada ambiente)

Use as versões exatas coletadas no Passo 3. Versão exata (`=`) é intencional: evita upgrades silenciosos em ambientes de time. O relatório deve orientar sobre atualização controlada.

```hcl
terraform {
  required_version = "= <TERRAFORM_VERSION>"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= <AWS_PROVIDER_VERSION>"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### main.tf (em cada ambiente)

```hcl
# Ambiente: <env>
# Adicione seus recursos aqui.
#
# Para usar um módulo local:
# module "exemplo" {
#   source = "../../modules/exemplo"
# }
```

### variables.tf (em cada ambiente)

```hcl
variable "aws_region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}
```

### outputs.tf (em cada ambiente)

```hcl
# Defina outputs aqui.
# Exemplo:
# output "vpc_id" {
#   value = module.vpc.vpc_id
# }
```

### terraform.tfvars.example (em cada ambiente)

```hcl
aws_region = "us-east-1"
```

Renomeie para `terraform.tfvars` e ajuste os valores antes de usar.

### .terraform-version

Conteúdo: apenas a versão do Terraform (sem `=`), para uso com `tfenv`:

```
<TERRAFORM_VERSION>
```

### .gitignore

```gitignore
# Estado Terraform — nunca commitar
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.backup
crash.log

# Variáveis com valores reais — usar .tfvars.example no lugar
*.tfvars
!*.tfvars.example

# Overrides locais
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

### modules/README.md

```markdown
# Módulos

Coloque módulos Terraform reutilizáveis aqui, cada um em seu próprio subdiretório:

​```
modules/
└── <nome-modulo>/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── README.md
​```

Para referenciar um módulo a partir de um ambiente:

​```hcl
module "<nome>" {
  source = "../../modules/<nome-modulo>"

  # passe as variáveis necessárias
}
​```
```

## Passo 6 — Formatar

Execute `terraform fmt -recursive` na raiz do projeto gerado:

```bash
terraform fmt -recursive <nome-projeto>/
```

Se falhar por algum motivo, informe no relatório mas não bloqueie a entrega.

## Passo 7 — Gerar TERRAFORM_SETUP.md

Crie o relatório na raiz do projeto gerado. Use este template exato:

```markdown
# Terraform Setup — <nome-projeto>

## Versões

| Componente       | Versão      | Fonte                                      |
|------------------|-------------|---------------------------------------------|
| Terraform CLI    | = X.Y.Z     | checkpoint-api.hashicorp.com               |
| AWS Provider     | = A.B.C     | registry.terraform.io/providers/hashicorp/aws |

## Estrutura gerada

​```
<nome-projeto>/
├── modules/
│   └── README.md
├── environments/
<lista de ambientes gerados>
├── .terraform-version
├── .gitignore
└── TERRAFORM_SETUP.md
​```

## Ambientes

<lista de ambientes com uma linha de descrição cada>

## Primeiros passos

1. Entre no ambiente desejado: `cd <nome-projeto>/environments/<env>`
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
```

## Passo 8 — Apresentar resultado

Ao final, mostre ao usuário:
- Caminho do projeto criado
- Versões usadas (Terraform + AWS provider)
- Lista de arquivos gerados
- Próximo passo imediato (entrar no diretório e rodar `terraform init`)
