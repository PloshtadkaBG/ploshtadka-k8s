#!/usr/bin/env bash
# seal.sh — create or re-seal Kubernetes secrets for PloshtadkaBG
#
# Prerequisites:
#   brew install kubeseal   (or the equivalent for your OS)
#   kubectl context pointed at the target cluster
#
# Usage:
#   ./scripts/seal.sh [namespace]          # seal ALL secrets
#   ./scripts/seal.sh [namespace] db       # seal only db-credentials
#   ./scripts/seal.sh [namespace] users    # seal only users-ms-secrets
#   ./scripts/seal.sh [namespace] payments # seal only payments-ms-secrets
#
# Run this whenever you need to rotate a secret value. The resulting
# sealed-secrets/*.yaml files are safe to commit to Git.

set -euo pipefail

NS=${1:-default}
TARGET=${2:-all}
OUT=sealed-secrets

seal_db() {
  echo "  → ploshtadka-db-credentials"
  read -rs -p "  PostgreSQL password: " PG_PASS; echo
  kubectl create secret generic ploshtadka-db-credentials \
    --namespace "$NS" \
    --from-literal=username=ploshtadka \
    --from-literal=password="$PG_PASS" \
    --dry-run=client -o yaml \
    | kubeseal --format yaml \
    > "$OUT/db-credentials.yaml"
}

seal_users() {
  echo "  → users-ms-secrets"
  read -rs -p "  SECRET_KEY (JWT signing key): " SECRET_KEY; echo
  read -r  -p "  GOOGLE_CLIENT_ID: " GOOGLE_CLIENT_ID
  read -r  -p "  SMTP_HOST [smtp.gmail.com]: " SMTP_HOST; SMTP_HOST=${SMTP_HOST:-smtp.gmail.com}
  read -r  -p "  SMTP_PORT [587]: " SMTP_PORT; SMTP_PORT=${SMTP_PORT:-587}
  read -r  -p "  SMTP_USER: " SMTP_USER
  read -rs -p "  SMTP_PASSWORD: " SMTP_PASSWORD; echo
  kubectl create secret generic users-ms-secrets \
    --namespace "$NS" \
    --from-literal=SECRET_KEY="$SECRET_KEY" \
    --from-literal=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
    --from-literal=SMTP_HOST="$SMTP_HOST" \
    --from-literal=SMTP_PORT="$SMTP_PORT" \
    --from-literal=SMTP_USER="$SMTP_USER" \
    --from-literal=SMTP_PASSWORD="$SMTP_PASSWORD" \
    --dry-run=client -o yaml \
    | kubeseal --format yaml \
    > "$OUT/users-ms-secrets.yaml"
}

seal_payments() {
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
}

echo "Sealing secrets for namespace: $NS"

case "$TARGET" in
  db)       seal_db ;;
  users)    seal_users ;;
  payments) seal_payments ;;
  all)      seal_db; seal_users; seal_payments ;;
  *)        echo "Unknown target: $TARGET (use: db, users, payments, or all)"; exit 1 ;;
esac

echo ""
echo "Done. Commit the files in $OUT/ — they are encrypted and safe for Git."
echo "Apply them with:  kubectl apply -f $OUT/"
