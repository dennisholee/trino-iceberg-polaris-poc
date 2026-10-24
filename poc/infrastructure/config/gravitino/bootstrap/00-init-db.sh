#!/usr/bin/env bash
# Create/upgrade the Gravitino PostgreSQL entity store for the POC.
# Safe to run repeatedly. Run from poc/infrastructure (the script finds it).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${INFRA_DIR}"

DB_EXISTS="$(docker compose exec -T postgres psql -U polaris -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='gravitino'" | tr -d '[:space:]')"

if [ "${DB_EXISTS}" != "1" ]; then
  echo "Creating database gravitino..."
  docker compose exec -T postgres psql -U polaris -d postgres -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE gravitino"
else
  echo "Database gravitino already exists."
fi

echo "Ensuring schema gravitino..."
docker compose exec -T postgres psql -U polaris -d gravitino -v ON_ERROR_STOP=1 \
  -c "CREATE SCHEMA IF NOT EXISTS gravitino"

SCHEMA_EXISTS="$(docker compose exec -T postgres psql -U polaris -d gravitino -tAc \
  "SELECT 1 FROM information_schema.tables WHERE table_schema='gravitino' AND table_name='metalake_meta'" | tr -d '[:space:]')"

if [ "${SCHEMA_EXISTS}" != "1" ]; then
  echo "Applying official Gravitino 1.3.0 schema..."
  docker compose exec -T postgres psql -U polaris -d gravitino -v ON_ERROR_STOP=1 \
    -c "SET search_path TO gravitino" \
    -f /docker-entrypoint-initdb.d/gravitino/schema-1.3.0-postgresql.psql
else
  echo "Gravitino schema already present; skipping schema apply."
fi

echo "Gravitino entity store ready."
