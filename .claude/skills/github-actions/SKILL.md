---
name: github-actions
description: >
  Cria e padroniza workflows GitHub Actions seguindo 6 regras de boas práticas. Use esta skill
  sempre que o usuário quiser criar um novo workflow de CI/CD, auditar workflows existentes,
  corrigir violações em pipelines, ou padronizar o .github/workflows/. Dispara para pedidos como
  "cria um workflow", "audita meu CI", "tem violations no meu github actions", "adiciona pipeline",
  "meu workflow tá errado", "padroniza os workflows", "fix my pipeline", "quero CI/CD com docker",
  ou qualquer menção a GitHub Actions, workflows, CI/CD, ou .github/. Sempre busca versões reais
  das actions via GitHub API e consulta context7 para sintaxe — nunca escreve actions de memória.
---

# GitHub Actions — Padronização e Boas Práticas

## O que esta skill faz

Opera em dois modos dependendo do contexto:

- **CRIAR**: Gera novo workflow do zero em `.github/workflows/`
- **AUDITAR**: Lê workflows existentes, identifica violações das 6 regras, propõe diff e aplica após confirmação

## Passo 1 — Detectar o modo

```bash
find . -path "./.github/workflows/*.yml" -o -path "./.github/workflows/*.yaml" 2>/dev/null
```

- Nenhum arquivo encontrado → **modo CRIAR**
- Arquivos encontrados → pergunte: criar novo ou auditar os existentes?

---

## Modo CRIAR

### Passo C1 — Coletar informações

Se não estiverem no prompt, pergunte:
- **Propósito**: build+push de imagem? testes? deploy? lint?
- **Trigger**: push na `main`? `pull_request`? schedule?
- **Registry de destino**: GHCR, Docker Hub, ECR, DOCR, GCR?

### Passo C2 — Buscar versões reais das actions (paralelo)

Para cada action necessária, busque via WebFetch:
```
https://api.github.com/repos/<owner>/<repo>/releases/latest
→ campo "tag_name"
```

Actions mais comuns:
| Action | Repositório GitHub |
|--------|--------------------|
| `actions/checkout` | `actions/checkout` |
| `actions/setup-node` | `actions/setup-node` |
| `docker/login-action` | `docker/login-action` |
| `docker/build-push-action` | `docker/build-push-action` |
| `docker/metadata-action` | `docker/metadata-action` |
| `aws-actions/configure-aws-credentials` | `aws-actions/configure-aws-credentials` |
| `google-github-actions/auth` | `google-github-actions/auth` |
| `digitalocean/action-doctl` | `digitalocean/action-doctl` |

Nunca use versões de memória — elas ficam desatualizadas silenciosamente.

### Passo C3 — Consultar context7

Para cada action que será usada, consulte o context7:
- `resolve-library-id` com o nome da action (ex: `"docker build-push-action github actions"`)
- `query-docs` focando nos inputs do bloco `with:` e comportamento esperado

Context7 é para consulta de documentação — não para executar o workflow.

### Passo C4 — Gerar o workflow

Aplique todas as 6 regras ao gerar. Crie em `.github/workflows/<nome-descritivo>.yml`.

**Template base:**
```yaml
name: <Nome Descritivo>

on:
  push:
    branches: [main]

permissions:
  contents: read
  # adicione apenas as permissões necessárias

env:
  IMAGE: <registry>/<nome-imagem>

jobs:
  <nome-job>:
    name: <Descrição do Job>
    runs-on: ubuntu-latest
    timeout-minutes: 20

    steps:
      - name: Checkout
        uses: actions/checkout@<VERSÃO-REAL-DA-API>

      # demais steps com actions de publishers oficiais
      # tag de imagem sempre com ${{ github.run_number }}
```

---

## Modo AUDITAR

### Passo A1 — Ler todos os workflows

Leia cada arquivo em `.github/workflows/`.

### Passo A2 — Verificar as 6 regras

Para cada workflow, cheque cada regra e registre violations.

### Passo A3 — Apresentar relatório

Antes de qualquer edição, mostre:

```
## Violations em .github/workflows/ci-cd.yml

[R1] Tag de imagem: usa `github.sha` → deve usar `github.run_number`
[R2] actions/checkout@v4 → versão genérica; versão exata: @v4.2.2
[R3] Sem bloco `permissions:` no workflow
[R4] Job `build` sem `timeout-minutes`

Total: 4 violations
```

### Passo A4 — Mostrar diff proposto

Para cada arquivo com violations, exiba o diff antes/depois.

### Passo A5 — Confirmar e aplicar

Pergunte: **"Aplicar essas correções?"** antes de editar qualquer arquivo.

Para R5 (secret hardcoded): apenas sinaliza, não substitui automaticamente. O usuário precisa criar o secret no GitHub antes.

---

## As 6 Regras

### R1 — Tag de imagem: `github.run_number`

`run_number` é sequencial e legível — facilita identificar qual build gerou qual imagem e fazer rollback. `github.sha` é imutável mas ilegível. `latest` é perigoso pois sobrescreve sem rastreabilidade.

```yaml
# ❌
tags: ${{ env.IMAGE }}:${{ github.sha }}
tags: ${{ env.IMAGE }}:latest

# ✓
tags: ${{ env.IMAGE }}:${{ github.run_number }}
```

### R2 — Versões de actions: exatas, nunca `@main` ou `@latest`

`@main` e `@latest` podem introduzir breaking changes silenciosamente. Versão exata garante reprodutibilidade. Versão major (`@v4`) é genérica demais — pode mudar a qualquer patch.

```yaml
# ❌
uses: actions/checkout@main
uses: actions/checkout@latest
uses: actions/checkout@v4   # genérico

# ✓
uses: actions/checkout@v4.2.2  # buscado via GitHub API
```

### R3 — `permissions:` explícito

O padrão do GitHub é permissivo demais (`write-all` em repositórios privados). Declarar explicitamente segue o princípio do mínimo privilégio e é exigência de auditorias de segurança.

```yaml
permissions:
  contents: read
  packages: write  # somente se fizer push para GHCR
```

Adicione no nível do workflow (vale para todos os jobs) ou por job individualmente.

### R4 — `timeout-minutes:` em todo job

Sem timeout, um job travado consome minutos do plano indefinidamente. Um timeout força falha explícita em vez de silêncio.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 20  # 10 para jobs simples, 20 para builds, 30 para deploys
```

### R5 — Sem secrets hardcoded

Credenciais no código ficam expostas no histórico git e nos logs mesmo após remoção.

```yaml
# ❌
- run: docker login -u admin -p minhaSenha123

# ✓
- uses: docker/login-action@v3.3.0
  with:
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_PASSWORD }}
```

Ao encontrar valor literal suspeito: sinalizar e orientar o usuário a criar o secret em **Settings → Secrets and variables → Actions**.

### R6 — Actions oficiais no lugar de scripts manuais

Actions de publishers verificados encapsulam tratamento de erro, compatibilidade cross-platform e atualizações de segurança. Scripts `run:` precisam reinventar isso e são frágeis.

Publishers reconhecidos: `actions/`, `docker/`, `aws-actions/`, `google-github-actions/`, `azure/`, `hashicorp/`, `digitalocean/`

Substituições frequentes:
| Script manual (`run:`) | Action oficial |
|------------------------|----------------|
| `docker login ...` | `docker/login-action` |
| `docker build ... && docker push ...` | `docker/build-push-action` |
| `aws configure ...` | `aws-actions/configure-aws-credentials` |
| `curl ... doctl ...` | `digitalocean/action-doctl` |
| `git checkout ...` | `actions/checkout` |

Sempre consulte context7 para a sintaxe exata do bloco `with:` antes de substituir — os inputs variam entre actions e versões.
