# Postmortem — Setup de Cluster Kubernetes Local (kube-news)

**Data:** 16 de maio de 2026  
**Ambiente:** WSL2 + Docker Desktop + kind v0.23.0  
**Projeto:** kube-news (Node.js + Express + PostgreSQL)  
**Status final:** Resolvido ✅

---

## Resumo Executivo

Durante o processo de containerização e deploy do kube-news em um cluster Kubernetes local com kind, foram encontrados dois incidentes que impediram o funcionamento inicial da aplicação. Ambos foram identificados, corrigidos e documentados como aprendizado na skill `local-k8s`. O sistema ficou operacional em aproximadamente 30 minutos após o início do troubleshooting.

---

## Linha do Tempo

| Hora | Evento |
|------|--------|
| ~18:00 | Início do setup — criação dos manifestos K8s e `setup.sh` |
| ~18:05 | Instalação de `kind` e `kubectl` em `~/.local/bin` (sem sudo) |
| ~18:10 | Execução do `setup.sh` — cluster kind criado, imagem buildada e carregada |
| ~18:12 | **Incidente 1:** MetalLB rejeita o IPAddressPool — erro de subnet inválida |
| ~18:15 | Root cause identificado: subnet IPv6 retornada antes da IPv4 |
| ~18:17 | Fix aplicado: filtro `grep -v ':'` para isolar subnet IPv4 |
| ~18:18 | MetalLB configurado com sucesso, IP externo `172.18.255.200` atribuído |
| ~18:20 | **Incidente 2:** pod `kube-news` em CrashLoopBackOff após postgres subir |
| ~18:22 | Root cause identificado: `readinessProbe` usando `/healthz` (inexistente) |
| ~18:24 | Fix aplicado: caminho corrigido para `/ready` (confirmado em `system-life.js`) |
| ~18:25 | Todos os pods em `1/1 Running`, acesso via `localhost:8080` confirmado |

---

## Incidentes

### Incidente 1 — MetalLB rejeitou o IPAddressPool (IPv6 Bug)

**Sintoma:**
```
Error from server (Forbidden): admission webhook denied the request:
invalid CIDR "fc00:f853:ccd:e793::/64.255.200-..." in pool "default-pool"
```

**Root Cause:**  
O comando `docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}'` retorna o primeiro item da lista de configurações de rede do kind. Neste ambiente, o primeiro item era a subnet **IPv6** (`fc00:f853:ccd:e793::/64`), não a IPv4. O MetalLB não aceita endereços IPv6 no `IPAddressPool` quando configurado em modo L2.

**Impacto:**  
- MetalLB instalado mas sem pool válido
- Service `kube-news` teria ficado em `<pending>` indefinidamente
- Acesso externo à aplicação impossível

**Resolução:**  
Substituir a extração do primeiro item pela filtragem explícita por IPv4:

```bash
# Antes (quebrado)
SUBNET=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')

# Depois (correto)
SUBNET=$(docker network inspect kind \
  -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' \
  | tr ' ' '\n' | grep -v ':' | head -1)
```

---

### Incidente 2 — Pod em CrashLoopBackOff por ReadinessProbe incorreto

**Sintoma:**
```
NAME                         READY   STATUS             RESTARTS
kube-news-55f97477bd-6rkm2   0/1     CrashLoopBackOff   4
```

**Root Cause:**  
O `readinessProbe` no manifesto `app-deployment.yaml` foi configurado com o caminho `/healthz`, um padrão genérico comum em aplicações K8s, mas que **não existe** nesta aplicação. Os endpoints reais de health foram definidos em `src/system-life.js` como:

- `GET /ready` → readiness (retorna 200 quando pronto)
- `GET /health` → liveness (retorna estado da máquina)

O Kubernetes interpretou as falhas consecutivas na probe como sinal para reiniciar o pod, gerando o loop.

**Fator agravante:**  
O CrashLoopBackOff inicial ocorreu também porque o pod da aplicação tentou conectar no PostgreSQL antes que o pod do banco estivesse pronto. O `readinessProbe` correto no Postgres (`pg_isready`) garantiria que o app só fosse marcado como ready após a dependência estar disponível — mas o problema da probe errada mascarou esse comportamento esperado.

**Impacto:**  
- Aplicação indisponível por ~5 minutos após o postgres ficar healthy
- Necessidade de `kubectl rollout restart` manual para recuperação

**Resolução:**  
1. Leitura do código-fonte antes de definir a probe (nunca assumir `/healthz`)
2. Correção no manifesto:

```yaml
# Antes
readinessProbe:
  httpGet:
    path: /healthz   # não existe
    port: 8080

# Depois
readinessProbe:
  httpGet:
    path: /ready     # confirmado em src/system-life.js
    port: 8080
```

---

## Causa Raiz Sistêmica

Ambos os incidentes têm a mesma causa raiz subjacente: **ausência de um processo padronizado para setup de K8s local com kind**. Sem um guia, cada tentativa depende do conhecimento do momento — e detalhes como o comportamento do kind com dual-stack IPv4/IPv6 e a necessidade de inspecionar o código para encontrar endpoints de health são facilmente esquecidos.

---

## Ações Corretivas

| Ação | Status | Artefato |
|------|--------|----------|
| Documentar o filtro IPv4 no `setup.sh` | ✅ Feito | `setup.sh` linha 21 |
| Corrigir `readinessProbe` para `/ready` | ✅ Feito | `k8s/app-deployment.yaml` |
| Criar skill `local-k8s` com os dois pitfalls documentados | ✅ Feito | `.claude/skills/local-k8s/SKILL.md` |
| Validar skill com evals (3 cenários, with/without skill) | ✅ Feito | `.claude/skills/local-k8s-workspace/` |
| Adicionar instrução na skill: "leia o código-fonte antes de definir probes" | ✅ Feito | SKILL.md — Step 1 |

---

## Lições Aprendidas

1. **`docker network inspect` com kind retorna IPv6 antes de IPv4.** Sempre filtrar explicitamente com `grep -v ':'` ao extrair a subnet para o MetalLB.

2. **Nunca assumir o caminho da readinessProbe.** Ler o código-fonte antes de configurar. `/healthz` é uma convenção, não uma garantia.

3. **CrashLoopBackOff antes do banco estar ready é normal.** O K8s vai reiniciar o pod — isso é por design. O que importa é que a probe esteja correta para que o pod seja marcado como ready quando a dependência estiver disponível.

4. **`imagePullPolicy: Never` é obrigatório com kind.** Sem isso, o K8s tenta baixar a imagem de um registry externo e falha silenciosamente com `ImagePullBackOff`.

5. **WSL2 não expõe IPs do Docker para o Windows automaticamente.** O IP do MetalLB (`172.18.255.200`) só é acessível de dentro do WSL2. Para acessar do browser Windows, usar `kubectl port-forward svc/kube-news 8080:80`.

---

## Métricas da Skill criada

| Métrica | Com skill | Sem skill |
|---------|-----------|-----------|
| Taxa de acerto média | **95.2%** | 81.2% |
| Tempo médio de execução | **73.6s** | 105.3s |
| Tokens médios | **17.521** | 18.616 |
| IPv4 filter correto | ✅ 3/3 | ❌ 1/3 |
| imagePullPolicy: Never | ✅ 3/3 | ❌ 2/3 |

A skill elimina os dois bugs críticos em 100% dos casos testados.
