# Relatório de Violations — .github/workflows/ci-cd.yml

## Violations encontradas: 6

| Regra | Descrição | Linha |
|-------|-----------|-------|
| R1 | Tag de imagem usa `github.sha` e `latest` → deve usar `github.run_number` | 25, 26, 29, 30 |
| R2 | `actions/checkout@main` — versão inválida (`@main` nunca deve ser usado) | 14 |
| R3 | Sem bloco `permissions:` no workflow | — |
| R4 | Job `build-and-deploy` sem `timeout-minutes` | — |
| R6 | `curl` manual para instalar doctl → substituir por `digitalocean/action-doctl` | 17–20 |
| R6 | `docker build/push` manuals → substituir por `docker/build-push-action` | 25–30 |

## Diff proposto

```diff
+permissions:
+  contents: read
+
 jobs:
   build-and-deploy:
     runs-on: ubuntu-latest
+    timeout-minutes: 20

-      - name: Checkout
-        uses: actions/checkout@main
+      - name: Checkout
+        uses: actions/checkout@v6.0.2

-      - name: Instalar doctl
-        run: |
-          curl -sL https://github.com/digitalocean/doctl/releases/download/v1.101.0/doctl-1.101.0-linux-amd64.tar.gz | tar xz
-          sudo mv doctl /usr/local/bin
+      - name: Instalar doctl
+        uses: digitalocean/action-doctl@v2.5.2
+        with:
+          token: ${{ secrets.DIGITALOCEAN_ACCESS_TOKEN }}

-      - name: Build da imagem
-        run: |
-          docker build -t $IMAGE:${{ github.sha }} -t $IMAGE:latest .
-
-      - name: Push da imagem
-        run: |
-          docker push $IMAGE:${{ github.sha }}
-          docker push $IMAGE:latest
+      - name: Build e Push da imagem
+        uses: docker/build-push-action@v7.1.0
+        with:
+          context: .
+          push: true
+          tags: ${{ env.IMAGE }}:${{ github.run_number }}
```

## Versões buscadas via GitHub API

| Action | Versão atual |
|--------|-------------|
| `actions/checkout` | v6.0.2 |
| `digitalocean/action-doctl` | v2.5.2 |
| `docker/build-push-action` | v7.1.0 |
