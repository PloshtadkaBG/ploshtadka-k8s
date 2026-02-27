# ploshtadka-k8s

Helm umbrella chart for the PloshtadkaBG sports venue booking platform.

## Structure

```
Chart.yaml                  # Umbrella chart — depends on Redis only
values.yaml                 # Shared defaults
values.local.yaml           # Minikube overrides (imagePullPolicy: Never, domain: localhost)
values.staging.yaml         # Staging overrides
values.prod.yaml            # Production overrides (HA postgres, HPA, TLS)
templates/
  middlewares.yaml          # Shared Traefik Middleware CRDs (jwt-auth, api-strip, admin-strip)
  cluster.yaml              # CloudNativePG Cluster resource
charts/
  users-ms/                 # Auth service — JWT issuer + Traefik forwardAuth target
  venues-ms/                # Venues CRUD
  bookings-ms/              # Bookings + slots
  payments-ms/              # Stripe checkout + webhooks
  frontend/                 # TanStack Start SSR app
  admin-panel/              # React Router SPA
sealed-secrets/             # Encrypted secrets (safe to commit)
scripts/
  prerequisites.sh          # Install Traefik + CloudNativePG operators (run once per cluster)
  seal.sh                   # Create / rotate Sealed Secrets interactively
```

## Prerequisites

Install once per cluster before the first `helm install`:

```bash
# Local (no TLS)
./scripts/prerequisites.sh

# Production (with Let's Encrypt)
ACME_EMAIL=you@example.com ./scripts/prerequisites.sh
```

This installs:
- **Traefik** in namespace `traefik` — ingress controller with forwardAuth support
- **CloudNativePG operator** in namespace `cnpg-system` — manages the PostgreSQL cluster

These are kept out of the umbrella chart's `Chart.yaml` dependencies intentionally: they install CRDs that must exist in the cluster *before* the application manifests are rendered.

---

## Local development (Minikube)

### 1. Start Minikube

```bash
minikube start
minikube addons enable metrics-server
```

### 2. Install operators

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
./scripts/prerequisites.sh
```

### 3. Create dev secrets (plain — no kubeseal needed locally)

```bash
kubectl create secret generic ploshtadka-db-credentials \
  --from-literal=username=ploshtadka \
  --from-literal=password=devpassword

kubectl create secret generic ploshtadka-db-app \
  --from-literal=uri="asyncpg://ploshtadka:devpassword@ploshtadka-db-rw:5432/ploshtadka" \
  --from-literal=username=ploshtadka \
  --from-literal=password=devpassword

kubectl create secret generic users-ms-secrets \
  --from-literal=SECRET_KEY=dev-secret-key \
  --from-literal=GOOGLE_CLIENT_ID=<your-google-client-id>

kubectl create secret generic payments-ms-secrets \
  --from-literal=STRIPE_SECRET_KEY=sk_test_... \
  --from-literal=STRIPE_WEBHOOK_SECRET=whsec_...
```

### 4. Build images into Minikube

```bash
eval $(minikube docker-env)

docker build -t ghcr.io/ploshtadkabg/ploshtadka-users-ms:latest    ./ploshtadka-users-ms
docker build -t ghcr.io/ploshtadkabg/ploshtadka-venues-ms:latest   ./ploshtadka-venues-ms
docker build -t ghcr.io/ploshtadkabg/ploshtadka-bookings-ms:latest ./ploshtadka-bookings-ms
docker build -t ghcr.io/ploshtadkabg/ploshtadka-payments-ms:latest ./ploshtadka-payments-ms
docker build -t ghcr.io/ploshtadkabg/ploshtadka-frontend:latest    ./ploshtadka-frontend
docker build -t ghcr.io/ploshtadkabg/ploshtadka-admin-panel:latest ./ploshtadka-admin-panel
```

### 5. Install the chart

```bash
cd ploshtadka-k8s
helm dependency update
helm install ploshtadka . -f values.yaml -f values.local.yaml
```

### 6. Access services

```bash
# Expose Traefik locally — all services available at http://localhost:8080
kubectl port-forward -n traefik svc/traefik 8080:80

# Or access a service directly (bypasses Traefik)
kubectl port-forward svc/frontend 3000:3000
kubectl port-forward svc/admin-panel 5173:3000
```

### Updating after code changes

```bash
eval $(minikube docker-env)
docker build -t ghcr.io/ploshtadkabg/ploshtadka-users-ms:latest ./ploshtadka-users-ms
kubectl rollout restart deployment ploshtadka-users-ms
```

---

## Production deployment on a remote machine

### 1. Provision the server

| | Minimum | Comfortable |
|---|---|---|
| RAM | 4 GB | 8 GB |
| CPU | 2 vCPU | 4 vCPU |
| Disk | 40 GB SSD | 80 GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

Good options: **Hetzner CX32** (~€14/mo), DigitalOcean, Vultr.

Firewall: open ports **22** (SSH), **80** (HTTP / ACME challenge), **443** (HTTPS).

### 2. Install k3s

```bash
ssh root@<server-ip>

# Disable built-in Traefik — we install our own with ACME configured
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -

kubectl get nodes   # verify: status Ready
```

### 3. Configure kubectl on your local machine

```bash
# On server
sudo cat /etc/rancher/k3s/k3s.yaml
```

Copy the output to your local machine, replace `127.0.0.1` with `<server-ip>`:

```bash
# On local machine
mkdir -p ~/.kube
nano ~/.kube/ploshtadka-prod   # paste and replace 127.0.0.1 → <server-ip>

export KUBECONFIG=~/.kube/ploshtadka-prod
kubectl get nodes              # should show remote node as Ready
```

Add `export KUBECONFIG=~/.kube/ploshtadka-prod` to your `.zshrc` to make it permanent.

### 4. Point DNS to the server

At your DNS provider, create A records:

```
ploshtadka.bg      →  <server-ip>
www.ploshtadka.bg  →  <server-ip>
```

Verify propagation:
```bash
dig +short ploshtadka.bg   # must return <server-ip> before proceeding
```

### 5. Push images via CI

The GitHub Actions workflows in each service repo (`.github/workflows/ci.yml`) build and push to `ghcr.io/ploshtadkabg/<service>` automatically on every merge to `main`.

**One-time setup per repo** — add this GitHub Actions secret in each service repo that needs it:

| Repo | Secret name | Value |
|---|---|---|
| `ploshtadka-frontend` | `VITE_GOOGLE_CLIENT_ID` | Your Google OAuth client ID |

`GITHUB_TOKEN` (for ghcr.io push) is automatic — no setup needed.

After pushing to `main`, check that all 6 images appear at:
```
https://github.com/orgs/PloshtadkaBG/packages
```

Set each package visibility to **Public**, or create an image pull secret if you keep them private.

### 6. Install operators on the remote cluster

```bash
# Install Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
kubectl -n kube-system rollout status deploy/sealed-secrets-controller

# Install Traefik (with ACME) + CloudNativePG operator
cd ploshtadka-k8s
ACME_EMAIL=you@example.com ./scripts/prerequisites.sh
```

### 7. Seal production secrets

With `KUBECONFIG` pointing at the prod cluster:

```bash
./scripts/seal.sh
```

This prompts for each secret value interactively and writes encrypted YAML to `sealed-secrets/`. The resulting files are safe to commit.

```bash
git add sealed-secrets/
git commit -m "chore: add sealed secrets for prod"
git push
```

Apply the sealed secrets to the cluster:

```bash
kubectl apply -f sealed-secrets/
```

> **Note:** The `ploshtadka-db-app` secret is not sealed — it is created automatically by CloudNativePG when the cluster bootstraps. The DB URL scheme must be `asyncpg://` (Tortoise ORM requirement). If CloudNativePG creates it with `postgresql://`, recreate it manually:
> ```bash
> kubectl delete secret ploshtadka-db-app
> kubectl create secret generic ploshtadka-db-app \
>   --from-literal=uri="asyncpg://ploshtadka:<password>@ploshtadka-db-rw:5432/ploshtadka" \
>   --from-literal=username=ploshtadka \
>   --from-literal=password=<password>
> ```

### 8. Deploy

```bash
# Get the image SHA tags from the GitHub Actions run that built them
# (GitHub UI: repo → Actions → latest CI run → build-push step → image digest)

helm install ploshtadka . \
  -f values.yaml \
  -f values.prod.yaml \
  --set "users-ms.image.tag=<sha>" \
  --set "venues-ms.image.tag=<sha>" \
  --set "bookings-ms.image.tag=<sha>" \
  --set "payments-ms.image.tag=<sha>" \
  --set "frontend.image.tag=<sha>" \
  --set "admin-panel.image.tag=<sha>"

kubectl get pods -w   # watch everything come up
```

### 9. Verify

```bash
# TLS certificate is issued within ~60 seconds of first request
curl -I https://ploshtadka.bg/api/venues/
# Expected: HTTP/2 200, valid Let's Encrypt certificate

curl -I http://ploshtadka.bg/api/venues/
# Expected: 301 redirect → https://

curl -s https://ploshtadka.bg/api/bookings/ -w "\nstatus: %{http_code}\n"
# Expected: 401 (forwardAuth is working)
```

---

## Deploying updates

On every merge to `main`, CI builds a new image tagged with the commit SHA. To roll it out:

```bash
helm upgrade ploshtadka . \
  -f values.yaml \
  -f values.prod.yaml \
  --set "users-ms.image.tag=<new-sha>"   # only the services that changed
```

Kubernetes performs a rolling update — new pods start before old ones are terminated. With `replicaCount: 2` in `values.prod.yaml` there is no downtime.

To roll back to the previous version:
```bash
helm rollback ploshtadka
```

---

## Rotating secrets

```bash
# Re-run seal.sh (prompts for new values, overwrites sealed-secrets/)
./scripts/seal.sh

kubectl apply -f sealed-secrets/

# Restart affected pods to pick up the new secret values
kubectl rollout restart deployment ploshtadka-users-ms
kubectl rollout restart deployment ploshtadka-payments-ms
```

---

## Known quirks

| Issue | Cause | Fix |
|---|---|---|
| Init container `CreateContainerConfigError` | A referenced Secret doesn't exist yet | Create the missing secret; pod retries automatically |
| Init container `aerich init-db first` | Fresh database — no migration history | Fixed in chart: init container runs `upgrade \|\| init-db && upgrade` |
| `Unknown DB scheme: postgresql` | Tortoise ORM doesn't understand `postgresql://` | Use `asyncpg://` scheme in `ploshtadka-db-app` secret |
| IngressRoute 404 | Traefik `Host()` matcher requires exact hostname including case | Ensure `global.domain` matches the Host header exactly |
| forwardAuth 500 | Traefik in `traefik` ns cannot resolve short service name `users-ms` | Use FQDN: `users-ms.default.svc.cluster.local` (already fixed in `middlewares.yaml`) |
| CRD not found on `helm install` | Traefik/CNPG operators not installed yet | Run `prerequisites.sh` first |
