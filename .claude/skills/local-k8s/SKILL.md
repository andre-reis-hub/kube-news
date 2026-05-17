---
name: local-k8s
description: >
  Sets up a complete local Kubernetes environment for a Dockerized project using kind + MetalLB.
  Use this skill whenever the user wants to run a Docker or docker-compose application on a local
  Kubernetes cluster, asks for K8s manifests, mentions kind/minikube/k3d, wants to test their
  app in Kubernetes locally, or asks "how do I run this in K8s?". Even if they just say
  "quero testar no k8s" or "monta o k8s pra mim" — trigger this skill.
---

# Local Kubernetes Setup Skill

## What this skill does

Given a Dockerized project, produce:
1. A `k8s/` directory with all Kubernetes manifests
2. A `setup.sh` script that creates the cluster, installs MetalLB, and deploys everything

## Step 1 — Analyze the project

Before writing a single manifest, read:

- `Dockerfile` — understand the image, exposed port, and base image
- `docker-compose.yml` — map every service, env var, port, volume, and dependency
- Source code entry point (e.g. `server.js`, `app.py`, `main.go`) — find the actual **health/ready endpoints**. Do not assume `/healthz` or `/health`. Search for route definitions like `router.get('/ready', ...)` or `@app.route('/healthcheck')`. Using the wrong path causes the readinessProbe to fail silently.

## Step 2 — Design the manifest set

For each service in docker-compose, determine:

| Need | Manifest |
|---|---|
| Sensitive env vars (passwords, keys) | `Secret` (`stringData:`) |
| Non-sensitive env vars | `ConfigMap` or inline `env:` in Deployment |
| Stateful service (DB, cache) | `PersistentVolumeClaim` + `Deployment` |
| Stateless service (app) | `Deployment` only |
| Internal service (DB, cache) | `Service` with type `ClusterIP` |
| User-facing service | `Service` with type `LoadBalancer` |

**Naming convention**: one file per resource type per service.
```
k8s/
├── kind-config.yaml        ← kind cluster config (NOT a K8s manifest — exclude from kubectl apply)
├── postgres-secret.yaml
├── postgres-pvc.yaml
├── postgres-deployment.yaml
├── postgres-service.yaml
├── app-deployment.yaml
└── app-service.yaml
```

## Step 3 — Write the manifests

### Secrets
Use `stringData:` (plain text, Kubernetes encodes to base64 automatically):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
stringData:
  DB_PASSWORD: "mysecretpassword"
  DB_USERNAME: "myuser"
  DB_DATABASE: "mydb"
```

Reference in Deployments with `secretKeyRef`, never hardcode credentials in env vars.

### Deployments — critical details

For the **app** deployment:
- Set `imagePullPolicy: Never` — the image is loaded locally into kind, not pulled from a registry
- Set `DB_HOST` to the Kubernetes **Service name** of the database (not `localhost`)
- Use `secretKeyRef` for credentials from the Secret
- Set `readinessProbe` to the **real** health endpoint found in Step 1

```yaml
imagePullPolicy: Never  # required for local kind images
```

For **database** deployments:
- Add a `readinessProbe` using `exec` + `pg_isready` (or equivalent for other DBs)
- Mount the PVC at the data directory

### Services
- Database: `ClusterIP` (internal only) — port matches the DB default (5432 for Postgres)
- App: `LoadBalancer` — map port 80 → container port, **always set a fixed `nodePort`** (e.g. 30095) that matches the `kind-config.yaml` `extraPortMappings`

```yaml
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30095   # must match containerPort in kind-config.yaml
```

### kind-config.yaml — access from Windows/WSL2 without port-forward

Create `k8s/kind-config.yaml` with `extraPortMappings` so `localhost:<hostPort>` works directly from the Windows browser:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30095   # must match nodePort in app-service.yaml
        hostPort: 8080
        protocol: TCP
```

Create the cluster with: `kind create cluster --config k8s/kind-config.yaml`

## Step 4 — Write setup.sh

The script must run in this exact order (dependencies matter):

```bash
#!/bin/bash
set -e

# 1. Create cluster (with extraPortMappings for localhost access)
kind create cluster --config k8s/kind-config.yaml

# 2. Build and load image (before MetalLB to save time)
docker build -t <app-name>:latest .
kind load docker-image <app-name>:latest

# 3. Install MetalLB and wait for it to be ready
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=120s

# 4. Configure MetalLB — ALWAYS filter for IPv4
# kind's Docker network has both IPv4 and IPv6 subnets.
# The IPv6 entry comes first in the IPAM config, so you must
# explicitly filter it out, otherwise the IP pool will be invalid.
SUBNET=$(docker network inspect kind \
  -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' \
  | tr ' ' '\n' | grep -v ':' | head -1)
BASE=$(echo "$SUBNET" | cut -d. -f1-2)
START="${BASE}.255.200"
END="${BASE}.255.250"

kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - ${START}-${END}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
EOF

# 5. Apply manifests (exclude kind-config.yaml — it's not a K8s resource)
ls k8s/*.yaml | grep -v kind-config.yaml | xargs kubectl apply -f

# 6. Wait and report
kubectl wait --for=condition=ready pod --selector=app=<db-label> --timeout=120s
kubectl wait --for=condition=ready pod --selector=app=<app-label> --timeout=120s

EXTERNAL_IP=$(kubectl get svc <app-service-name> -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Acesse (Windows/WSL2): http://localhost:8080"
echo "Acesse (MetalLB IP):   http://${EXTERNAL_IP}"
```

Make the script executable (`chmod +x setup.sh`).

## Step 5 — Check for kind and kubectl

Before presenting the solution, check if `kind` and `kubectl` exist:

```bash
which kind 2>/dev/null || echo "missing"
which kubectl 2>/dev/null || echo "missing"
```

If missing, install to `~/.local/bin` (avoids needing sudo):

```bash
# kind
curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x /tmp/kind && mkdir -p ~/.local/bin && mv /tmp/kind ~/.local/bin/kind
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
export PATH=$PATH:$HOME/.local/bin

# kubectl
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -Lo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /tmp/kubectl && mv /tmp/kubectl ~/.local/bin/kubectl
```

## Common pitfalls to avoid

| Problem | Cause | Fix |
|---|---|---|
| MetalLB IPAddressPool rejected | IPv6 subnet used | Filter with `grep -v ':'` |
| App in CrashLoopBackOff on start | DB not ready yet | Normal — once DB is Ready the pod self-recovers. Use `kubectl rollout restart` to speed it up |
| readinessProbe always failing | Wrong endpoint path | Read actual route definitions in source code |
| Image not found in cluster | Forgot `kind load` | Always run `kind load docker-image` after `docker build` |
| `kubectl` connects to wrong cluster | Old kubeconfig | `kind` sets context automatically; verify with `kubectl config current-context` |
| `kubectl apply -f k8s/` fails with "no matches for kind Cluster" | `kind-config.yaml` não é um manifesto K8s | Use `ls k8s/*.yaml \| grep -v kind-config.yaml \| xargs kubectl apply -f` |
| `localhost:8080` recusado no Windows | `extraPortMappings` ausente ou `nodePort` divergente | `nodePort` no Service e `containerPort` no `kind-config.yaml` devem ser o mesmo valor |

## Verifying the deployment

After `./setup.sh`, check with:

```bash
kubectl get pods          # all should be 1/1 Running
kubectl get svc           # app service should show EXTERNAL-IP
curl http://<EXTERNAL-IP> # or open in browser
```

If a pod stays in `CrashLoopBackOff` after all dependencies are running, check logs:
```bash
kubectl logs deployment/<app-name>
```
