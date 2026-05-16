# Rodando sua API Node no Kubernetes local

Nenhuma experiencia previa com Kubernetes necessaria. Esse guia te leva do zero ate acessar sua app no browser.

## O que foi feito (analise do seu projeto)

Antes de gerar qualquer arquivo, analisei seu projeto:

- **Dockerfile**: imagem `node:18-alpine`, app roda na porta **8080** (nao 3000 como voce mencionou — o Dockerfile e o server.js usam 8080)
- **docker-compose.yml**: dois servicos — `app` (sua API) e `db` (postgres:14-alpine)
- **server.js + system-life.js**: encontrei os endpoints reais de health:
  - `/ready` — readiness probe (retorna 200 quando pronto)
  - `/health` — liveness probe (retorna JSON com estado)

---

## Pre-requisitos

**kind e kubectl ja estao instalados** em `~/.local/bin` no seu sistema. Voce pode pular a etapa de instalacao.

Para confirmar:
```bash
kind version
kubectl version --client
```

Voce tambem precisa ter o **Docker** rodando.

---

## Arquivos gerados

```
outputs/
├── k8s/
│   ├── postgres-secret.yaml      # credenciais do banco (base64 automatico)
│   ├── postgres-pvc.yaml         # volume persistente para os dados do postgres
│   ├── postgres-deployment.yaml  # pod do postgres com readiness via pg_isready
│   ├── postgres-service.yaml     # servico interno ClusterIP na porta 5432
│   ├── app-deployment.yaml       # pod da sua API Node
│   └── app-service.yaml          # LoadBalancer na porta 80 -> container 8080
└── setup.sh                      # script que faz tudo automaticamente
```

---

## Como usar

### 1. Copie os arquivos para a raiz do seu projeto

```bash
cp -r k8s/ /caminho/do/seu/projeto/
cp setup.sh /caminho/do/seu/projeto/
```

Os arquivos devem ficar assim na raiz do projeto:
```
seu-projeto/
├── Dockerfile
├── docker-compose.yml
├── src/
├── k8s/
│   └── *.yaml
└── setup.sh
```

### 2. Torne o script executavel e rode

```bash
chmod +x setup.sh
./setup.sh
```

O script faz tudo na ordem certa:
1. Cria o cluster kind
2. Builda sua imagem Docker e carrega no cluster
3. Instala o MetalLB (load balancer local)
4. Configura um pool de IPs locais para o MetalLB
5. Aplica todos os manifests Kubernetes
6. Aguarda os pods ficarem prontos
7. Exibe o IP para voce acessar no browser

### 3. Acesse no browser

Ao final do script voce vera algo como:
```
==================================================
  Tudo pronto! Acesse no browser:
  http://172.18.255.200
==================================================
```

Abra esse IP no seu browser — voce vai ver sua aplicacao rodando.

---

## Verificando se esta tudo ok

```bash
# Ver status dos pods (todos devem mostrar 1/1 Running)
kubectl get pods

# Ver o IP externo do servico
kubectl get svc

# Ver logs da sua app se algo der errado
kubectl logs deployment/kube-news

# Ver logs do postgres
kubectl logs deployment/postgres
```

---

## Explicacao dos conceitos principais (para quem nunca mexeu com K8s)

| Conceito | O que e | Equivalente no docker-compose |
|---|---|---|
| **Pod** | Menor unidade — roda um container | Container |
| **Deployment** | Gerencia pods, faz restart automatico | `restart: on-failure` |
| **Service ClusterIP** | Acesso interno entre pods | Nome do servico no docker network |
| **Service LoadBalancer** | Expoe para fora do cluster | `ports: "8080:8080"` |
| **Secret** | Guarda dados sensiveis | Variaveis de ambiente sensiveis |
| **PVC** | Volume persistente | `volumes:` no docker-compose |
| **MetalLB** | Fornece IPs reais para LoadBalancer em ambiente local | Nao existe equivalente — e exclusivo do K8s local |

---

## Pontos importantes descobertos na analise

1. **Porta real e 8080, nao 3000** — voce mencionou porta 3000, mas o Dockerfile e o server.js usam 8080. Os manifests ja estao corretos com 8080.

2. **imagePullPolicy: Never** — configurado no app-deployment.yaml. Sem isso, o Kubernetes tentaria baixar a imagem do Docker Hub (e falharia porque nao existe la). O `kind load docker-image` carrega a imagem diretamente no cluster.

3. **DB_HOST = "postgres"** — no Kubernetes, os pods se comunicam pelo nome do Service, nao por `localhost`. O Service do postgres se chama `postgres`, entao `DB_HOST=postgres` funciona exatamente como `DB_HOST=db` funcionava no docker-compose.

4. **CrashLoopBackOff na inicializacao e normal** — se a sua app tentar conectar no banco antes dele estar pronto, o pod vai falhar e reiniciar automaticamente. Isso e esperado. Uma vez que o postgres estiver pronto (1/1 Running), a app sobe normalmente.

---

## Para derrubar o cluster quando terminar

```bash
kind delete cluster
```

Isso remove tudo — cluster, pods, services. Os dados do banco sao perdidos (e um ambiente de teste, nao producao).
