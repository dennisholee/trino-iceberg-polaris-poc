#!/usr/bin/env bash
# Verify the Gravitino metadata plane and the Polaris federation.
# Tables may be absent if the data path has not been run yet; that is not a
# failure for this spike. Catalogs must exist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

GRAVITINO_URL="${GRAVITINO_URL:-http://localhost:8090}"
METALAKE="${GRAVITINO_METALAKE:-poc}"
ACCEPT="application/vnd.gravitino.v1+json"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

POLARIS_TOKEN="$(polaris_token)" || { echo "Polaris token unavailable" >&2; exit 1; }
AUTH_HEADER="Authorization: Bearer ${POLARIS_TOKEN}"

show() {
  local label="$1" path="$2" required="${3:-false}"
  echo
  echo "=== ${label} ==="
  local code="000" attempt
  # Catalog creation can return before the backend is fully initialized; retry briefly.
  for attempt in $(seq 1 5); do
    code="$(curl -sS -o "${TMP}" -w '%{http_code}' -H "Accept: ${ACCEPT}" \
      -H "${AUTH_HEADER}" "${GRAVITINO_URL}${path}")" || code="000"
    [ "${code}" = "200" ] && break
    sleep 2
  done
  echo "GET ${path} -> HTTP ${code}"
  if [ "${code}" = "200" ]; then
    jq . "${TMP}" 2>/dev/null || cat "${TMP}"
  elif [ "${code}" = "404" ]; then
    echo "(not created yet)"
    [ "${required}" = "true" ] && return 1
  else
    cat "${TMP}" 2>/dev/null || true
    [ "${required}" = "true" ] && return 1
  fi
  return 0
}

show "Metalake" "/api/metalakes/${METALAKE}" true
show "Catalogs" "/api/metalakes/${METALAKE}/catalogs" true
show "Kafka schemas" "/api/metalakes/${METALAKE}/catalogs/kafka/schemas" false
show "Kafka topics (default schema)" "/api/metalakes/${METALAKE}/catalogs/kafka/schemas/default/topics" false
show "Iceberg schemas (Polaris proxy)" "/api/metalakes/${METALAKE}/catalogs/iceberg/schemas" false
show "Iceberg tables (poc schema)" "/api/metalakes/${METALAKE}/catalogs/iceberg/schemas/poc/tables" false

echo
echo "Verification complete. If the Iceberg tables are empty, run the data path first"
echo "(Trino DDL + Connect sink) and re-run this script."
