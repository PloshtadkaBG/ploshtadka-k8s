#!/usr/bin/env bash
# seal.sh — create or re-seal Kubernetes secrets for PloshtadkaBG
#
# Prerequisites:
#   brew install kubeseal   (or the equivalent for your OS)
#   kubectl context pointed at the target cluster
#
# Usage:
#   ./scripts/seal.sh [namespace]   (default namespace: default)
#
# Run this whenever you need to rotate a secret value. The resulting
# sealed-secrets/*.yaml files are safe to commit to Git.

set -euo pipefail

NS=${1:-default}
OUT=sealed-secrets

echo "Sealing secrets for namespace: $NS"

# ─── Database credentials (consumed by CloudNativePG Cluster bootstrap) ──────
echo "  → ploshtadka-db-credentials"
read -rs -p "  PostgreSQL password: " PG_PASS; echo
kubectl create secret generic ploshtadka-db-credentials \
  --namespace "$NS" \
  --from-literal=password="$PG_PASS" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
  > "$OUT/db-credentials.yaml"

# ─── users-ms (SECRET_KEY + GOOGLE_CLIENT_ID) ────────────────────────────────
echo "  → users-ms-secrets"
read -rs -p "  SECRET_KEY (JWT signing key): " SECRET_KEY; echo
read -r  -p "  GOOGLE_CLIENT_ID: " GOOGLE_CLIENT_ID
kubectl create secret generic users-ms-secrets \
  --namespace "$NS" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  --from-literal=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
  > "$OUT/users-ms-secrets.yaml"

# ─── payments-ms (STRIPE_SECRET_KEY + STRIPE_WEBHOOK_SECRET) ─────────────────
echo "  → payments-ms-secrets"
read -rs -p "  STRIPE_SECRET_KEY: " STRIPE_KEY; echo
read -rs -p "  STRIPE_WEBHOOK_SECRET: " STRIPE_WEBHOOK; echo
kubectl create secret generic payments-ms-secrets \
  --namespace "$NS" \
  --from-literal=STRIPE_SECRET_KEY="$STRIPE_KEY" \
  --from-literal=STRIPE_WEBHOOK_SECRET="$STRIPE_WEBHOOK" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
  > "$OUT/payments-ms-secrets.yaml"

echo ""
echo "Done. Commit the files in $OUT/ — they are encrypted and safe for Git."
echo "Apply them with:  kubectl apply -f $OUT/"
