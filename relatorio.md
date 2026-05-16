# Proposta de Arquitetura Cloud — kube-news na AWS
**Documento para Aprovação — Diretoria e Equipe de Negócio**

| | |
|---|---|
| **Projeto** | kube-news |
| **Versão** | 1.0 |
| **Data** | 16/05/2026 |
| **Status** | Aguardando Aprovação |

---

## Sumário Executivo

O projeto kube-news é uma aplicação web de portal de notícias desenvolvida em Node.js com banco de dados PostgreSQL, empacotada em container Docker. O presente documento propõe a migração e hospedagem desta aplicação na Amazon Web Services (AWS), com arquitetura desenhada para atender aos requisitos de disponibilidade, segurança, escalabilidade e custo-eficiência.

A arquitetura recomendada utiliza **Amazon ECS Fargate** para execução dos containers sem gerenciamento de servidores e **Amazon RDS PostgreSQL Multi-AZ** para o banco de dados com failover automático entre zonas de disponibilidade. Essa combinação elimina a sobrecarga operacional de infraestrutura, garante alta disponibilidade e permite escalar a capacidade de forma proporcional à demanda.

O custo estimado para o ambiente de produção é de aproximadamente **USD 176/mês**, com retorno de investimento justificado pela eliminação de infraestrutura on-premises e redução de horas operacionais de manutenção.

---

## 1. Problema

### 1.1 Contexto Atual

A aplicação kube-news está em fase de desenvolvimento e requer um ambiente de produção para ser disponibilizada ao público-alvo. Atualmente não há infraestrutura definida para hospedagem, gerando os seguintes riscos e limitações:

- **Ausência de ambiente produtivo:** a aplicação não possui hosting definido, impedindo lançamento ao mercado.
- **Escalabilidade manual:** sem orquestração de containers, o crescimento de usuários demandaria intervenção manual para adição de capacidade.
- **Risco de indisponibilidade:** sem estratégia de failover, qualquer falha de hardware ou software derrubaria a aplicação por períodos indefinidos.
- **Gerenciamento de banco de dados:** sem solução gerenciada, a equipe precisaria administrar manualmente backups, patches e recuperação de desastres do PostgreSQL.
- **Segurança não padronizada:** a ausência de WAF e controles de rede expõe a aplicação a ataques como SQL Injection e Cross-Site Scripting.

### 1.2 Requisitos da Solução

| Requisito | Descrição |
|---|---|
| Disponibilidade | SLA mínimo de 99,9% (downtime máximo de ~8,7h/ano) |
| Escalabilidade | Capacidade de aumentar instâncias automaticamente sob alta demanda |
| Segurança | Proteção contra ataques web, credenciais protegidas, rede isolada |
| Failover | Recuperação automática de falhas em menos de 2 minutos |
| Deploy | Pipeline automatizado com rollback em caso de falha |
| Observabilidade | Logs centralizados, métricas e alertas operacionais |

---

## 2. Arquitetura Proposta

### 2.1 Visão Geral

A solução adota uma arquitetura em camadas, com separação entre rede pública, camada de aplicação e camada de dados, distribuída em múltiplas Zonas de Disponibilidade (AZs) da região **us-east-1 (N. Virginia)**.

```
                         INTERNET
                             │
                    ┌────────▼────────┐
                    │   Route 53      │  DNS gerenciado com health checks
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   AWS WAF       │  Proteção OWASP, bloqueio de SQLi/XSS
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │      ALB        │  Application Load Balancer (porta 443/HTTPS)
                    │  Certificado    │  Certificado SSL gratuito via ACM
                    │  ACM (HTTPS)    │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
    ┌──────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐
    │ ECS Fargate │   │ ECS Fargate │   │ ECS Fargate │
    │  kube-news  │   │  kube-news  │   │  kube-news  │
    │   (AZ-1a)   │   │   (AZ-1b)   │   │   (AZ-1c)   │
    └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
           │                 │                 │
           └─────────────────┼─────────────────┘
                             │  (Subnets Privadas)
                    ┌────────▼────────┐
                    │  RDS PostgreSQL │
                    │    Multi-AZ     │
                    │ Primary (AZ-1a) │──── Standby (AZ-1b) [failover automático]
                    └─────────────────┘

  ┌──────────────────────────────────────────────────────────────┐
  │                    Serviços de Suporte                       │
  │                                                              │
  │  ┌───────────┐  ┌─────────────────┐  ┌──────────────────┐   │
  │  │    ECR    │  │ Secrets Manager │  │   CloudWatch     │   │
  │  │ (imagens) │  │  (credenciais)  │  │ (logs/métricas)  │   │
  │  └───────────┘  └─────────────────┘  └──────────────────┘   │
  │                                                              │
  │  ┌───────────┐  ┌─────────────────┐                         │
  │  │    IAM    │  │  NAT Gateway    │                         │
  │  │  (roles)  │  │ (acesso externo │                         │
  │  └───────────┘  │  das tasks)     │                         │
  │                 └─────────────────┘                         │
  └──────────────────────────────────────────────────────────────┘
```

### 2.2 Componentes e Justificativas

#### Amazon ECS Fargate (Computação)
- Executa os containers da aplicação sem necessidade de provisionar ou gerenciar servidores EC2.
- A aplicação já possui endpoints `/health` e `/ready` implementados, aproveitados nativamente pelo ECS para verificação de saúde das tasks.
- **Auto Scaling** aumenta ou reduz o número de tasks automaticamente com base em CPU, memória ou número de requisições via ALB.
- Deploy com **rolling update**: novas versões sobem gradualmente enquanto a versão anterior permanece ativa, validada pelo endpoint `/ready`, garantindo zero downtime.

#### Amazon RDS PostgreSQL Multi-AZ (Banco de Dados)
- Banco de dados totalmente gerenciado: patches de segurança, backups automáticos (retenção configurável de até 35 dias) e snapshots sem intervenção da equipe.
- **Multi-AZ** mantém uma instância standby sincronizada em AZ diferente. Em caso de falha da instância primária, o failover ocorre automaticamente em aproximadamente 60 segundos, sem alteração de connection string na aplicação.
- As variáveis de ambiente já configuradas na aplicação (`DB_HOST`, `DB_PORT`, `DB_PASSWORD`) são gerenciadas via **Secrets Manager**, eliminando credenciais hardcoded em imagens ou arquivos de configuração.

#### Application Load Balancer (Balanceamento de Carga)
- Distribui requisições entre tasks Fargate em múltiplas AZs.
- Termina conexões HTTPS com certificado gratuito via **AWS Certificate Manager (ACM)**.
- Health checks automáticos apontam para o endpoint `/health` da aplicação, removendo tasks não saudáveis do pool de balanceamento.
- Permite restringir o endpoint `/metrics` (Prometheus) a acesso interno apenas.

#### AWS WAF (Segurança de Aplicação)
- Camada de proteção posicionada na frente do ALB.
- Bloqueia os ataques mais comuns do OWASP Top 10, incluindo SQL Injection, Cross-Site Scripting (XSS) e requisições malformadas.
- Especialmente relevante dado que a aplicação possui vulnerabilidades conhecidas em versão de desenvolvimento.

#### AWS Secrets Manager (Gestão de Credenciais)
- Armazena credenciais do banco de dados (`DB_PASSWORD`, `DB_USERNAME`) com rotação automática configurável.
- Tasks Fargate lêem os segredos em runtime via IAM Role, sem que as credenciais apareçam em variáveis de ambiente visíveis ou em logs.

#### Amazon ECR (Registro de Imagens)
- Repositório privado para as imagens Docker da aplicação.
- Scan automático de vulnerabilidades (CVEs) em cada imagem enviada ao repositório, bloqueando deploys com falhas críticas de segurança.
- Transferências entre ECR e Fargate na mesma região são **gratuitas**.

#### Amazon CloudWatch (Observabilidade)
- Centraliza logs de todas as tasks Fargate.
- **Container Insights** coleta métricas de CPU, memória, rede e disco por task e por serviço.
- A aplicação já exporta métricas no formato Prometheus via endpoint `/metrics`, que podem ser raspadas e enviadas ao CloudWatch ou ao Amazon Managed Prometheus.
- Alertas configuráveis via SNS (e-mail, SMS, Slack) para eventos críticos.

#### Amazon Route 53 (DNS)
- Gerencia o domínio da aplicação com health checks no ALB.
- Em caso de falha regional, suporta roteamento de failover para ambiente de contingência.

### 2.3 Segurança em Camadas

| Camada | Controle |
|---|---|
| Rede | Subnets privadas para Fargate e RDS; apenas ALB na subnet pública |
| Perímetro | WAF com ruleset OWASP gerenciado pela AWS |
| Transporte | HTTPS obrigatório com TLS 1.2+ via ACM |
| Identidade | IAM Roles com princípio do menor privilégio; sem credenciais hardcoded |
| Credenciais | Secrets Manager com rotação automática |
| Imagens | ECR com scan de CVEs antes de cada deploy |
| Acesso DB | Security Group restrito: apenas tasks Fargate acessam a porta 5432 |

### 2.4 Pipeline de Deploy (CI/CD)

```
Commit no GitHub
      │
      ▼
GitHub Actions / AWS CodePipeline
      │
      ├── Build da imagem Docker
      ├── Push para Amazon ECR
      ├── Scan de vulnerabilidades (ECR Inspector)
      │
      ▼
ECS Rolling Update
      │
      ├── Nova task sobe com nova imagem
      ├── ALB verifica /ready (health check)
      ├── Task aprovada → entra no pool
      └── Task antiga → removida do pool
```

---

## 3. Custo

> Os preços abaixo são referentes à região **us-east-1 (N. Virginia)** e foram obtidos nas páginas oficiais de pricing da AWS em maio de 2026. Os valores estão em dólares americanos (USD). Taxas de câmbio não estão inclusas. Para RDS PostgreSQL, a tabela de preços por instância utiliza conteúdo dinâmico na página oficial; a estimativa de instância foi calculada com base na estrutura de preços confirmada pelo AWS Pricing Calculator.

### 3.1 Estimativa — Ambiente de Produção

| Serviço | Configuração | Cálculo | Custo/mês (USD) |
|---|---|---|---|
| **ECS Fargate** | 2 tasks × 0,5 vCPU × 1 GB RAM, 730h | vCPU: 2×0,5×$0,04048×730 + Mem: 2×1×$0,004445×730 | **$36,00** |
| **RDS PostgreSQL** | db.t3.micro Multi-AZ + 20 GB gp2 | ~$0,036/h × 730h + 20GB × $0,115 | **$28,60** |
| **ALB** | 1 instância + ~1 LCU | $0,0225×730 + $0,008×1×730 | **$22,24** |
| **NAT Gateway** | 2 AZs + ~10 GB processados | 2×$0,045×730 + 2×10×$0,045 | **$66,60** |
| **AWS WAF** | 1 Web ACL + 5 regras + 1M req/mês | $5 + 5×$1 + 1×$0,60 | **$10,60** |
| **Amazon ECR** | ~2 GB de imagens | 2×$0,10 | **$0,20** |
| **Secrets Manager** | 3 segredos | 3×$0,40 | **$1,20** |
| **Route 53** | 1 hosted zone + 1M queries | $0,50 + 1×$0,40 | **$0,90** |
| **CloudWatch** | ~5 GB logs + Container Insights | 5×$0,50 + 5×$0,03 + métricas | **$7,65** |
| | | **Total mensal estimado** | **≈ USD 174,00** |
| | | **Total anual estimado** | **≈ USD 2.088,00** |

### 3.2 Estimativa — Ambiente de Desenvolvimento/Homologação

| Serviço | Configuração | Custo/mês (USD) |
|---|---|---|
| ECS Fargate | 1 task × 0,25 vCPU × 0,5 GB | **$4,50** |
| RDS PostgreSQL | db.t3.micro Single-AZ + 20 GB gp2 | **$15,60** |
| ALB | 1 instância, tráfego mínimo | **$17,00** |
| NAT Gateway | 1 AZ | **$33,75** |
| CloudWatch | logs mínimos | **$3,00** |
| Outros | ECR, Secrets Manager, Route 53 | **$2,50** |
| | **Total mensal estimado** | **≈ USD 76,35** |
| | **Total anual estimado** | **≈ USD 916,20** |

### 3.3 Custo Total Consolidado

| Ambiente | Mensal (USD) | Anual (USD) |
|---|---|---|
| Produção | ~174,00 | ~2.088,00 |
| Dev / Homologação | ~76,35 | ~916,20 |
| **Total** | **~250,35** | **~3.004,20** |

> **Oportunidade de economia:** instâncias reservadas (Reserved Instances) com compromisso de 1 ano oferecem desconto de até 40% sobre o preço on-demand para RDS e até 36% para outros serviços, podendo reduzir o custo anual total para aproximadamente **USD 1.900,00**.

---

## 4. Cronograma de Implementação

A implementação está dividida em três fases, com duração total estimada de **6 semanas**. Cada fase entrega valor independente e permite validação antes do avanço à fase seguinte.

### Fase 1 — Fundação de Infraestrutura (Semanas 1–2)

**Objetivo:** Provisionar toda a infraestrutura base na AWS de forma segura e versionada via Infrastructure as Code (IaC).

| # | Atividade | Responsável | Duração |
|---|---|---|---|
| 1.1 | Criação da conta AWS e configuração de billing alerts | DevOps | 1 dia |
| 1.2 | Provisionamento da VPC com subnets públicas e privadas em 3 AZs | DevOps | 2 dias |
| 1.3 | Configuração de Security Groups por camada (ALB, Fargate, RDS) | DevOps | 1 dia |
| 1.4 | Provisionamento do RDS PostgreSQL Multi-AZ com Secrets Manager | DevOps | 2 dias |
| 1.5 | Criação do repositório ECR e políticas IAM | DevOps | 1 dia |
| 1.6 | Configuração do NAT Gateway nas AZs | DevOps | 1 dia |
| 1.7 | Validação de conectividade e testes de segurança de rede | DevOps + Segurança | 2 dias |

**Entregável:** Infraestrutura base funcionando, banco de dados acessível internamente, repositório de imagens configurado.

---

### Fase 2 — Deploy da Aplicação e CI/CD (Semanas 3–4)

**Objetivo:** Colocar a aplicação no ar em ambiente de homologação, com pipeline automatizado de build e deploy.

| # | Atividade | Responsável | Duração |
|---|---|---|---|
| 2.1 | Criação do cluster ECS e definição de task (CPU, memória, variáveis) | DevOps | 1 dia |
| 2.2 | Configuração do ALB com target group e health checks em `/health` | DevOps | 1 dia |
| 2.3 | Configuração do ACM (certificado SSL) e Route 53 (domínio) | DevOps | 1 dia |
| 2.4 | Configuração do serviço ECS com Auto Scaling e rolling update | DevOps | 2 dias |
| 2.5 | Implementação do pipeline CI/CD (GitHub Actions → ECR → ECS) | DevOps + Dev | 2 dias |
| 2.6 | Configuração do AWS WAF com regras OWASP gerenciadas | Segurança | 1 dia |
| 2.7 | Deploy em homologação e testes funcionais completos | Dev + QA | 2 dias |

**Entregável:** Aplicação rodando em homologação com HTTPS, deploy automatizado via git push, WAF ativo.

---

### Fase 3 — Observabilidade, Hardening e Go-Live (Semanas 5–6)

**Objetivo:** Garantir visibilidade operacional completa, realizar testes de carga e promover a aplicação para produção com segurança.

| # | Atividade | Responsável | Duração |
|---|---|---|---|
| 3.1 | Configuração do CloudWatch Container Insights e dashboards | DevOps | 2 dias |
| 3.2 | Configuração de alertas (CPU, memória, erros 5xx, latência) via SNS | DevOps | 1 dia |
| 3.3 | Configuração de log retention e exportação para S3 (auditoria) | DevOps | 1 dia |
| 3.4 | Teste de carga e validação do Auto Scaling | DevOps + QA | 2 dias |
| 3.5 | Simulação de failover do RDS e validação de recuperação | DevOps | 1 dia |
| 3.6 | Revisão final de segurança (IAM, Security Groups, WAF logs) | Segurança | 1 dia |
| 3.7 | Documentação operacional (runbook, plano de disaster recovery) | DevOps | 1 dia |
| 3.8 | Go-live em produção com monitoramento intensivo nas primeiras 24h | DevOps + Dev | 1 dia |

**Entregável:** Aplicação em produção, 100% observável, documentada, com plano de DR testado e aprovado.

---

### Linha do Tempo

```
Semana:    1          2          3          4          5          6
           ├──────────┤──────────┤──────────┤──────────┤──────────┤
FASE 1:    [██████████████████]
           Infraestrutura Base

FASE 2:                        [██████████████████]
                                Deploy + CI/CD

FASE 3:                                           [██████████████████]
                                                  Observabilidade + Go-Live
```

---

## 5. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Atraso na aprovação de contas AWS corporativas | Média | Alto | Iniciar processo de criação da conta na Fase 0 (pré-projeto) |
| Custos acima do estimado por tráfego inesperado | Baixa | Médio | Budget Alerts configurados no AWS Billing para 80% e 100% do orçamento |
| Falha no failover do banco de dados | Baixa | Alto | Teste de failover obrigatório na Fase 3 antes do go-live |
| Vulnerabilidades na imagem Docker | Média | Alto | Scan automático no ECR bloqueia deploys com CVEs críticas |
| Indisponibilidade da região us-east-1 | Muito baixa | Alto | RDS Multi-AZ protege contra falhas de AZ; falha regional exigiria DR em segunda região |

---

## Referências

As informações de preço e especificações técnicas foram extraídas exclusivamente de fontes oficiais da Amazon Web Services:

- [Amazon ECS Fargate Pricing](https://aws.amazon.com/fargate/pricing/)
- [Amazon RDS for PostgreSQL Pricing](https://aws.amazon.com/rds/postgresql/pricing/)
- [Amazon RDS Pricing (Overview)](https://aws.amazon.com/rds/pricing/)
- [Elastic Load Balancing Pricing — ALB](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [Amazon VPC Pricing — NAT Gateway](https://aws.amazon.com/vpc/pricing/)
- [AWS WAF Pricing](https://aws.amazon.com/waf/pricing/)
- [Amazon ECR Pricing](https://aws.amazon.com/ecr/pricing/)
- [AWS Secrets Manager Pricing](https://aws.amazon.com/secrets-manager/pricing/)
- [Amazon Route 53 Pricing](https://aws.amazon.com/route53/pricing/)
- [Amazon CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/)
- [AWS Pricing Calculator](https://calculator.aws/#/addService/RDSPostgreSQL)

> **Nota:** As tabelas de preços de instâncias RDS utilizam conteúdo dinâmico (JavaScript) na página oficial, não acessível via scraping automatizado. Os valores de instância foram estimados com base na estrutura de preços documentada pela AWS e validados via AWS Pricing Calculator. Recomenda-se confirmar os valores atualizados diretamente no [AWS Pricing Calculator](https://calculator.aws/) antes da aprovação final do orçamento.
