# Como rodar o kube-news no Kubernetes local

Boa notícia: você não precisa de servidor nem de conta em nuvem. Tudo vai rodar
na sua máquina usando **kind** — uma ferramenta que cria um cluster Kubernetes
real dentro de containers Docker.

---

## O que você vai instalar

| Ferramenta | Para que serve | Link |
|---|---|---|
| **Docker** | Obrigatório — o kind roda dentro dele | https://docs.docker.com/get-docker/ |
| **kind** | Cria o cluster Kubernetes local | https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| **kubectl** | CLI para conversar com o cluster | https://kubernetes.io/docs/tasks/tools/ |

> Se já tiver Docker instalado, só falta o kind e o kubectl.

---

## Instalação rápida (Linux / WSL2)

```bash
# kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
```

---

## Como funciona — visão geral

```
Seu browser (localhost:8080)
        |
        v
  kind (cluster k8s dentro do Docker)
        |
        +-- Service NodePort :30080 --> Pod kube-news (app Node.js :8080)
                                              |
                                        Service ClusterIP
                                              |
                                         Pod postgres (:5432)
                                              |
                                        PersistentVolumeClaim
                                        (dados do banco salvos em disco)
```

Conceitos básicos que você vai encontrar nos arquivos:

- **Pod**: a menor unidade do k8s — é onde seu container roda.
- **Deployment**: garante que o número certo de Pods esteja sempre rodando.
- **Service**: expõe um Deployment para receber tráfego. Tipos usados aqui:
  - `ClusterIP` — só acessível dentro do cluster (banco de dados).
  - `NodePort` — acessível de fora do cluster pelo browser (sua app).
- **Secret**: guarda senhas e dados sensíveis de forma segura.
- **PersistentVolumeClaim (PVC)**: pede um pedaço de disco para o banco não
  perder dados quando o Pod reiniciar.
- **kind-config.yaml**: ensina o kind a expor a porta 30080 do cluster como
  a porta 8080 da sua máquina — é isso que permite abrir no browser.

---

## Subindo com um comando só

A partir da **raiz do projeto** (onde fica o `Dockerfile`):

```bash
# Dê permissão de execução ao script (só na primeira vez)
chmod +x .claude/skills/local-k8s-workspace/iteration-1/first-time-k8s/without_skill/outputs/setup.sh

# Execute
.claude/skills/local-k8s-workspace/iteration-1/first-time-k8s/without_skill/outputs/setup.sh
```

O script faz automaticamente:
1. Verifica se Docker, kind e kubectl estão instalados.
2. Cria o cluster kind com a configuração de porta correta.
3. Faz o build da sua imagem Docker (`kube-news:latest`).
4. Carrega a imagem dentro do cluster (passo crítico — o kind não enxerga as
   imagens do seu Docker diretamente).
5. Aplica todos os arquivos YAML do diretório `k8s/`.
6. Aguarda os Pods ficarem prontos.

Depois de concluir, abra: **http://localhost:8080**

---

## Passo a passo manual (se preferir entender cada etapa)

### 1. Criar o cluster

```bash
kind create cluster --name kube-news \
  --config .claude/skills/local-k8s-workspace/iteration-1/first-time-k8s/without_skill/outputs/k8s/kind-config.yaml
```

### 2. Build da imagem

```bash
# Execute da raiz do projeto (onde fica o Dockerfile)
docker build -t kube-news:latest .
```

### 3. Carregar a imagem no cluster

```bash
# IMPORTANTE: sem esse passo a app não sobe (ImagePullBackOff)
kind load docker-image kube-news:latest --name kube-news
```

### 4. Aplicar os manifests

```bash
K8S=.claude/skills/local-k8s-workspace/iteration-1/first-time-k8s/without_skill/outputs/k8s

kubectl apply -f $K8S/namespace.yaml
kubectl apply -f $K8S/postgres-secret.yaml
kubectl apply -f $K8S/postgres-pvc.yaml
kubectl apply -f $K8S/postgres-deployment.yaml
kubectl apply -f $K8S/postgres-service.yaml
kubectl apply -f $K8S/app-deployment.yaml
kubectl apply -f $K8S/app-service.yaml
```

### 5. Verificar se está tudo rodando

```bash
kubectl get pods -n kube-news
```

Saída esperada (pode demorar ~60s para STATUS virar `Running`):
```
NAME                         READY   STATUS    RESTARTS   AGE
kube-news-xxxxx-xxxxx        1/1     Running   0          45s
postgres-xxxxx-xxxxx         1/1     Running   0          50s
```

### 6. Acessar no browser

```
http://localhost:8080
```

---

## Comandos úteis do dia a dia

```bash
# Ver status dos pods
kubectl get pods -n kube-news

# Ver logs da aplicação Node.js
kubectl logs -n kube-news deploy/kube-news

# Ver logs do PostgreSQL
kubectl logs -n kube-news deploy/postgres

# Ver logs em tempo real (follow)
kubectl logs -n kube-news deploy/kube-news -f

# Descrever um pod (útil para debugar erros de startup)
kubectl describe pod -n kube-news -l app=kube-news

# Abrir um shell dentro do container da app
kubectl exec -it -n kube-news deploy/kube-news -- sh

# Reiniciar a aplicação (ex: após trocar a imagem)
kubectl rollout restart deployment/kube-news -n kube-news
```

---

## Atualizando a aplicação após mudança de código

```bash
# 1. Rebuildá a imagem
docker build -t kube-news:latest .

# 2. Carregar a nova imagem no kind
kind load docker-image kube-news:latest --name kube-news

# 3. Reiniciar o Deployment para pegar a nova imagem
kubectl rollout restart deployment/kube-news -n kube-news

# 4. Aguardar o rollout
kubectl rollout status deployment/kube-news -n kube-news
```

---

## Erros comuns e como resolver

| Erro | Causa | Solução |
|---|---|---|
| `ImagePullBackOff` | kind não encontrou a imagem | Rode `kind load docker-image kube-news:latest --name kube-news` |
| `CrashLoopBackOff` na app | App subiu antes do banco | Aguarde ~30s e rode `kubectl rollout restart deploy/kube-news -n kube-news` |
| `connection refused` no browser | Cluster ainda iniciando ou porta errada | Confira `kubectl get pods -n kube-news` e aguarde `Running` |
| `ECONNREFUSED` nos logs | DB_HOST errado | Deve ser `postgres` (nome do Service), não `localhost` |
| Pod fica em `Pending` | Recursos insuficientes (CPU/RAM) | Feche outros programas pesados; o kind precisa de ~2GB livres |

---

## Destruir tudo

```bash
kind delete cluster --name kube-news
```

Isso remove o cluster inteiro (containers, volumes do kind, configuração do
kubectl). Os dados do banco são perdidos junto — mas a PVC era local ao cluster.

---

## Estrutura dos arquivos gerados

```
outputs/
├── k8s/
│   ├── kind-config.yaml         # Configuração do cluster + mapeamento de portas
│   ├── namespace.yaml           # Namespace "kube-news" (isola seus recursos)
│   ├── postgres-secret.yaml     # Credenciais do banco (DB, user, password)
│   ├── postgres-pvc.yaml        # Pedido de disco para o banco (1Gi)
│   ├── postgres-deployment.yaml # Container postgres:14-alpine
│   ├── postgres-service.yaml    # Expõe o banco internamente (ClusterIP)
│   ├── app-deployment.yaml      # Container kube-news:latest (sua app Node.js)
│   └── app-service.yaml         # Expõe a app para o browser (NodePort :30080)
├── setup.sh                     # Script que automatiza tudo
└── response.md                  # Este arquivo
```
