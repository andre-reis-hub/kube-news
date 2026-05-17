# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Kube-News is a Node.js/Express news portal designed as a learning project for Docker and Kubernetes concepts. It demonstrates container orchestration, health probes, Prometheus metrics, and chaos engineering endpoints.

## Running the app

**With Docker Compose (recommended for local dev):**
```bash
docker-compose up --build
```
App is available at http://localhost:8080. Postgres starts first with a health check before the app connects.

**Directly (requires a running Postgres):**
```bash
cd src
npm install
node server.js
```

**Full local Kubernetes cluster (kind + MetalLB):**
```bash
bash setup.sh
```
Creates a kind cluster with `extraPortMappings` (`k8s/kind-config.yaml`), builds and loads the Docker image, installs MetalLB, applies all `k8s/` manifests (excluding `kind-config.yaml`), and prints the URL. App is accessible at `http://localhost:8080` from Windows/WSL2 — no port-forward needed.

## Environment variables

| Variable | Default |
|----------|---------|
| `DB_DATABASE` | `kubedevnews` |
| `DB_USERNAME` | `kubedevnews` |
| `DB_PASSWORD` | `Pg#123` |
| `DB_HOST` | `localhost` |
| `DB_PORT` | `5432` |
| `DB_SSL_REQUIRE` | `false` |

## Architecture

```
src/
  server.js       # Express entry point; mounts all routes
  system-life.js  # Health/readiness logic + chaos endpoints
  middleware.js   # Request counter middleware
  models/post.js  # Sequelize model + DB init (sync with alter:true on start)
  views/          # EJS templates
```

`models/post.js` calls `seque.sync({ alter: true })` on startup — schema migrations happen automatically at boot.

`system-life.js` exports two things mounted in `server.js`:
- `healthMid` — middleware that returns 500 for all requests when `isHealth = false` (triggered by `PUT /unhealth`)
- `routers` — handles `/health`, `/ready`, `/unhealth`, `/unreadyfor/:seconds`

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | List all posts |
| GET | `/post` | New post form |
| POST | `/post` | Create post (web form) |
| GET | `/post/:id` | View single post |
| POST | `/api/post` | Bulk create posts (JSON body: `{ artigos: [{title, resumo, description}] }`) |
| GET | `/health` | Returns `{ state, machine }` — always 200 unless `isHealth=false` |
| GET | `/ready` | Returns 200/500 — used as K8s readiness probe |
| GET | `/metrics` | Prometheus metrics (express-prom-bundle) |
| PUT | `/unhealth` | Makes app respond 500 to all requests (chaos) |
| PUT | `/unreadyfor/:seconds` | Makes `/ready` return 500 for N seconds (chaos) |

## Kubernetes manifests (`k8s/`)

- `postgres-secret.yaml` — base64-encoded DB credentials
- `postgres-pvc.yaml` — 1Gi PersistentVolumeClaim
- `postgres-deployment.yaml` + `postgres-service.yaml` — Postgres as ClusterIP `postgres:5432`
- `app-deployment.yaml` — kube-news with `imagePullPolicy: Never` (loads from kind) and readiness probe on `/ready`
- `app-service.yaml` — LoadBalancer service (MetalLB provides external IP)
- `kind-config.yaml` — kind cluster config with hostPort 8080 → containerPort 30095

## Populating data

Use `popula-dados.http` with VS Code REST Client or curl to bulk-insert sample articles via `POST /api/post`.

## No tests

There are no automated tests (`npm test` exits with an error). Manual testing via browser or `popula-dados.http` is the current approach.
