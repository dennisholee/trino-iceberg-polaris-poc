#!/usr/bin/env bash
# Register the POC metalake and catalogs in Gravitino.
# The Iceberg catalog is a REST proxy to Polaris; no metadata is copied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

GRAVITINO_URL="${GRAVITINO_URL:-http://localhost:8090}"
METALAKE="${GRAVITINO_METALAKE:-poc}"
ACCEPT="application/vnd.gravitino.v1+json"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

echo "Waiting for Polaris at ${POLARIS_URL}..."
POLARIS_TOKEN=""
for _ in $(seq 1 60); do
  if POLARIS_TOKEN="$(polaris_token)"; then break; fi
  sleep 2
done
[ -n "${POLARIS_TOKEN}" ] || { echo "Polaris token unavailable" >&2; exit 1; }
AUTH_HEADER="Authorization: Bearer ${POLARIS_TOKEN}"

RESP_CODE=""
do_request() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "${body}" ]; then
    RESP_CODE="$(curl -sS -o "${TMP}" -w '%{http_code}' -X "${method}" \
      -H "Accept: ${ACCEPT}" -H "Content-Type: application/json" \
      -H "${AUTH_HEADER}" --data "${body}" "${GRAVITINO_URL}${path}")" || RESP_CODE="000"
  else
    RESP_CODE="$(curl -sS -o "${TMP}" -w '%{http_code}' -X "${method}" \
      -H "Accept: ${ACCEPT}" -H "${AUTH_HEADER}" "${GRAVITINO_URL}${path}")" || RESP_CODE="000"
  fi
}

show_response_and_fail() {
  echo "Gravitino request failed (HTTP ${RESP_CODE}):" >&2
  cat "${TMP}" >&2 || true
  exit 1
}

echo "Waiting for Gravitino at ${GRAVITINO_URL}..."
for _ in $(seq 1 60); do
  do_request GET "/api/version"
  [ "${RESP_CODE}" = "200" ] && break
  sleep 2
done
[ "${RESP_CODE}" = "200" ] || show_response_and_fail

echo "Ensuring metalake ${METALAKE}..."
do_request GET "/api/metalakes/${METALAKE}"
case "${RESP_CODE}" in
  200) echo "Metalake already exists." ;;
  404)
    do_request POST "/api/metalakes" "$(jq -n --arg n "${METALAKE}" \
      '{name:$n, comment:"POC v2 metadata lake", properties:{}}')"
    case "${RESP_CODE}" in 200|201) echo "Metalake created." ;; *) show_response_and_fail ;; esac
    ;;
  *) show_response_and_fail ;;
esac

echo "Ensuring Kafka catalog..."
do_request GET "/api/metalakes/${METALAKE}/catalogs/kafka"
if [ "${RESP_CODE}" = "404" ]; then
  do_request POST "/api/metalakes/${METALAKE}/catalogs" "$(jq -n '{
    name:"kafka",
    type:"MESSAGING",
    provider:"kafka",
    comment:"POC domain-events topic metadata",
    properties:{"bootstrap.servers":"kafka:9092"}
  }')"
  case "${RESP_CODE}" in 200|201) echo "Kafka catalog created." ;; *) show_response_and_fail ;; esac
else
  [ "${RESP_CODE}" = "200" ] || show_response_and_fail
  echo "Kafka catalog already exists."
fi

echo "Ensuring Iceberg catalog (REST proxy to Polaris)..."
do_request GET "/api/metalakes/${METALAKE}/catalogs/iceberg"
if [ "${RESP_CODE}" = "404" ]; then
  # Gravitino's REST backend forwards the caller's Bearer token to Polaris via
  # UserPrincipalForwardingAuthManager. Static credential/scope properties are
  # ignored, so none are set here. No data-access mode is set: the POC disables
  # credential vending and only needs table metadata.
  do_request POST "/api/metalakes/${METALAKE}/catalogs" "$(jq -n '{
    name:"iceberg",
    type:"RELATIONAL",
    provider:"lakehouse-iceberg",
    comment:"Polaris Iceberg REST proxy (metadata only)",
    properties:{
      "catalog-backend":"rest",
      "uri":"http://polaris:8181/api/catalog",
      "warehouse":"poc",
      "catalog-backend-name":"poc"
    }
  }')"
  case "${RESP_CODE}" in 200|201) echo "Iceberg catalog created." ;; *) show_response_and_fail ;; esac
else
  [ "${RESP_CODE}" = "200" ] || show_response_and_fail
  echo "Iceberg catalog already exists."
fi

echo
echo "Registered catalogs:"
do_request GET "/api/metalakes/${METALAKE}/catalogs"
[ "${RESP_CODE}" = "200" ] || show_response_and_fail
jq . "${TMP}" 2>/dev/null || cat "${TMP}"
