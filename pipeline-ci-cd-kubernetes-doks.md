# Pipeline CI/CD — Kube-News no DOKS

Deploy automatizado via GitHub Actions: build da imagem Docker, push no DigitalOcean Container Registry (DOCR) e rollout no cluster DOKS a cada push na branch `main`.

---

## Fluxo do Pipeline

```
git push → main
      │
      ▼
┌──────────────────────────────────────────────┐
│                GitHub Actions                │
│                                              │
│  1. Checkout do código                       │
│  2. Login no DOCR                            │
│  3. Build da imagem Docker                   │
│  4. Push da imagem (tag: SHA do commit)      │
│  5. Instalar doctl + kubectl                 │
│  6. kubectl set image → Deployment no DOKS   │
└──────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────┐
│  DOKS (cluster Kubernetes)  │
│  Rolling update automático  │
│  Readiness probe valida pod │
│  antes de cortar o tráfego  │
└─────────────────────────────┘
```

---

## Pré-requisitos

| Recurso | Onde criar |
|---------|-----------|
| Conta DigitalOcean | cloud.digitalocean.com |
| Cluster DOKS | Kubernetes → Create Cluster |
| Container Registry | Container Registry → Create Registry |
| Personal Access Token | API → Generate New Token (read + write) |

---

## Arquivos necessários no repositório

```
kube-news/
├── Dockerfile                        ← build da imagem
├── k8s/
│   ├── postgres-secret.yaml
│   ├── postgres-pvc.yaml
│   ├── postgres-deployment.yaml
│   ├── postgres-service.yaml
│   ├── app-deployment.yaml           ← imagem atualizada pelo pipeline
│   └── app-service.yaml
└── .github/
    └── workflows/
        └── ci-cd.yml                 ← definição do pipeline
```

---

## 1. Dockerfile

```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY src/package*.json ./
RUN npm install --production

COPY src/ .

EXPOSE 8080

CMD ["node", "server.js"]
```

---

## 2. Manifestos Kubernetes (`k8s/`)

### `k8s/postgres-secret.yaml`
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
data:
  POSTGRES_DB: a3ViZWRldm5ld3M=       # kubedevnews (base64)
  POSTGRES_USER: a3ViZWRldm5ld3M=     # kubedevnews (base64)
  POSTGRES_PASSWORD: UGcjMTIz         # Pg#123 (base64)
```

> Para gerar: `echo -n "valor" | base64`

### `k8s/postgres-pvc.yaml`
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### `k8s/postgres-deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:14-alpine
          envFrom:
            - secretRef:
                name: postgres-secret
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "kubedevnews", "-d", "kubedevnews"]
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: postgres-pvc
```

### `k8s/postgres-service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
```

### `k8s/app-deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-news
spec:
  replicas: 2
  selector:
    matchLabels:
      app: kube-news
  template:
    metadata:
      labels:
        app: kube-news
    spec:
      containers:
        - name: kube-news
          image: registry.digitalocean.com/SEU-REGISTRY/kube-news:latest
          ports:
            - containerPort: 8080
          env:
            - name: DB_HOST
              value: postgres
            - name: DB_PORT
              value: "5432"
            - name: DB_DATABASE
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_DB
            - name: DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: POSTGRES_PASSWORD
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
```

### `k8s/app-service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: kube-news
spec:
  type: LoadBalancer
  selector:
    app: kube-news
  ports:
    - port: 80
      targetPort: 8080
```

> No DOKS, `type: LoadBalancer` provisiona automaticamente um DigitalOcean Load Balancer com IP público.

---

## 3. Pipeline GitHub Actions

### Secrets necessários no repositório

Adicionar em **Settings → Secrets and variables → Actions**:

| Secret | Valor |
|--------|-------|
| `DIGITALOCEAN_ACCESS_TOKEN` | Token com permissão read/write (API → Tokens) |
| `DOCR_ENDPOINT` | `registry.digitalocean.com/nome-do-seu-registry` |
| `DOKS_CLUSTER_NAME` | Nome do cluster (ex: `kube-news-cluster`) |

### `.github/workflows/ci-cd.yml`

```yaml
name: CI/CD — Kube-News DOKS

on:
  push:
    branches:
      - main

env:
  IMAGE: ${{ secrets.DOCR_ENDPOINT }}/kube-news

jobs:
  build-and-deploy:
    name: Build, Push e Deploy
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Instalar doctl
        uses: digitalocean/action-doctl@v2
        with:
          token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

      - name: Login no Container Registry
        run: doctl registry login --expiry-seconds 600

      - name: Build da imagem Docker
        run: |
          docker build -t $IMAGE:${{ github.sha }} -t $IMAGE:latest .

      - name: Push da imagem
        run: |
          docker push $IMAGE:${{ github.sha }}
          docker push $IMAGE:latest

      - name: Configurar kubectl para o DOKS
        run: |
          doctl kubernetes cluster kubeconfig save ${{ secrets.DOKS_CLUSTER_NAME }}

      - name: Aplicar manifestos (primeira vez)
        run: |
          kubectl apply -f k8s/postgres-secret.yaml
          kubectl apply -f k8s/postgres-pvc.yaml
          kubectl apply -f k8s/postgres-deployment.yaml
          kubectl apply -f k8s/postgres-service.yaml
          kubectl apply -f k8s/app-deployment.yaml
          kubectl apply -f k8s/app-service.yaml

      - name: Atualizar imagem no Deployment
        run: |
          kubectl set image deployment/kube-news \
            kube-news=$IMAGE:${{ github.sha }}

      - name: Aguardar rollout
        run: |
          kubectl rollout status deployment/kube-news --timeout=120s

      - name: Exibir IP do LoadBalancer
        run: |
          kubectl get svc kube-news
```

---

## Primeiro deploy (setup manual)

Na primeira vez, o cluster ainda não tem nenhum recurso. Faça o setup inicial com `doctl` e `kubectl` na sua máquina:

```bash
# 1. Autenticar no DigitalOcean
doctl auth init

# 2. Baixar kubeconfig do cluster
doctl kubernetes cluster kubeconfig save kube-news-cluster

# 3. Verificar conexão
kubectl get nodes

# 4. Aplicar todos os manifestos
kubectl apply -f k8s/

# 5. Acompanhar o deploy
kubectl rollout status deployment/kube-news

# 6. Pegar o IP público
kubectl get svc kube-news
```

A partir do segundo deploy em diante, o pipeline cuida de tudo automaticamente.

---

## Variáveis de ambiente por contexto

| Variável | Valor no DOKS |
|----------|--------------|
| `DB_HOST` | `postgres` (nome do Service K8s) |
| `DB_PORT` | `5432` |
| `DB_DATABASE` | via Secret `postgres-secret` |
| `DB_USERNAME` | via Secret `postgres-secret` |
| `DB_PASSWORD` | via Secret `postgres-secret` |
| `DB_SSL_REQUIRE` | `false` (conexão interna ao cluster) |

---

## Estratégia de rollout

O `Deployment` usa **RollingUpdate** por padrão:
- Kubernetes sobe um pod novo com a imagem atualizada
- Aguarda a **readiness probe** (`GET /ready`) responder 200
- Só então derruba o pod antigo
- Se o rollout travar (probe falha por 120s), o pipeline retorna erro e o pod antigo continua servindo tráfego

Para reverter manualmente:

```bash
# Ver histórico de revisões
kubectl rollout history deployment/kube-news

# Voltar para a revisão anterior
kubectl rollout undo deployment/kube-news
```

---

## Troubleshooting

| Sintoma | Verificação |
|---------|-------------|
| Pod em `CrashLoopBackOff` | `kubectl logs deploy/kube-news` |
| Pod em `Pending` | `kubectl describe pod <nome>` — verificar recursos do node |
| Readiness probe falhando | `kubectl exec -it <pod> -- wget -qO- localhost:8080/ready` |
| Imagem não encontrada | Verificar se o registry está vinculado ao cluster: `doctl registry kubernetes-manifest \| kubectl apply -f -` |
| LoadBalancer sem IP | Aguardar ~2 min; verificar cotas de LB na conta DO |

### Vincular o registry ao cluster DOKS

O DOKS precisa de permissão para fazer pull das imagens privadas do DOCR:

```bash
doctl registry kubernetes-manifest | kubectl apply -f -
```

Isso cria um Secret do tipo `kubernetes.io/dockerconfigjson` no namespace `default`, que os pods usam automaticamente.
