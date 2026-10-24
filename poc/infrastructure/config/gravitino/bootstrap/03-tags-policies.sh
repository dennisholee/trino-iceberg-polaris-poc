#!/usr/bin/env bash
# Create POC tags and custom DQ policies, attach them to data assets, and verify
# inheritance. Gravitino 1.3.1 attaches policies directly to objects (not via tags).
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

POLARIS_TOKEN="$(polaris_token)" || { echo "Polaris token unavailable" >&2; exit 1; }
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

fail() {
  echo "$1" >&2
  cat "${TMP}" >&2 || true
  exit 1
}

ensure_tag() {
  local name="$1" comment="$2"
  do_request GET "/api/metalakes/${METALAKE}/tags/${name}"
  if [ "${RESP_CODE}" = "200" ]; then
    echo "tag ${name}: exists"
    return
  fi
  [ "${RESP_CODE}" = "404" ] || fail "tag ${name}: unexpected HTTP ${RESP_CODE}"
  do_request POST "/api/metalakes/${METALAKE}/tags" \
    "$(jq -n --arg n "${name}" --arg c "${comment}" \
      '{name:$n, comment:$c, properties:{}}')"
  case "${RESP_CODE}" in 200|201) echo "tag ${name}: created" ;; *) fail "tag ${name}: create failed" ;; esac
}

ensure_policy() {
  local name="$1" comment="$2" rules="$3" types="$4"
  do_request GET "/api/metalakes/${METALAKE}/policies/${name}"
  if [ "${RESP_CODE}" = "200" ]; then
    echo "policy ${name}: exists"
    return
  fi
  [ "${RESP_CODE}" = "404" ] || fail "policy ${name}: unexpected HTTP ${RESP_CODE}"
  do_request POST "/api/metalakes/${METALAKE}/policies" \
    "$(jq -n --arg n "${name}" --arg c "${comment}" \
      --argjson r "${rules}" --argjson t "${types}" \
      '{name:$n, comment:$c, policyType:"custom", enabled:true,
        content:{customRules:$r, supportedObjectTypes:$t, properties:{}}}')"
  case "${RESP_CODE}" in 200|201) echo "policy ${name}: created" ;; *) fail "policy ${name}: create failed" ;; esac
}

# Extract all names recursively; works for tags, policies and identifier lists.
# Gravitino returns bare names (not objects) unless details=true, so force it.
names_at() {
  local path="$1"
  if [[ "${path}" != *"details=true"* ]]; then
    if [[ "${path}" == *"?"* ]]; then path="${path}&details=true"; else path="${path}?details=true"; fi
  fi
  do_request GET "${path}"
  [ "${RESP_CODE}" = "200" ] || return 0
  jq -r '.. | objects | .name? // empty' "${TMP}" 2>/dev/null | sort -u
}

attach_tag() {
  local type="$1" name="$2" tag="$3"
  if names_at "/api/metalakes/${METALAKE}/objects/${type}/${name}/tags" | grep -qx "${tag}"; then
    echo "tag ${tag} on ${type} ${name}: already attached"
    return
  fi
  do_request POST "/api/metalakes/${METALAKE}/objects/${type}/${name}/tags" \
    "$(jq -n --arg t "${tag}" '{tagsToAdd:[$t]}')"
  case "${RESP_CODE}" in 200|201) echo "tag ${tag} on ${type} ${name}: attached" ;; *) fail "tag ${tag} on ${type} ${name}: attach failed" ;; esac
}

attach_policy() {
  local type="$1" name="$2" policy="$3"
  if names_at "/api/metalakes/${METALAKE}/objects/${type}/${name}/policies" | grep -qx "${policy}"; then
    echo "policy ${policy} on ${type} ${name}: already attached"
    return
  fi
  do_request POST "/api/metalakes/${METALAKE}/objects/${type}/${name}/policies" \
    "$(jq -n --arg p "${policy}" '{policiesToAdd:[$p]}')"
  case "${RESP_CODE}" in 200|201) echo "policy ${policy} on ${type} ${name}: attached" ;; *) fail "policy ${policy} on ${type} ${name}: attach failed" ;; esac
}

echo "Creating tags..."
ensure_tag "domain" "Business domain"
ensure_tag "pii" "Personally identifiable information"
ensure_tag "dq_tier" "Data-quality criticality"
ensure_tag "freshness_class" "Freshness expectation class"
ensure_tag "api_exposure" "API exposure classification"

echo
echo "Creating custom DQ policies..."
ensure_policy "dq_freshness_order" "Block stale order snapshots" \
  '{"maxLagSeconds":300,"action":"block","severity":"critical"}' '["SCHEMA","TABLE"]'
ensure_policy "dq_completeness_order" "Warn on incomplete order snapshots" \
  '{"maxNullRate":0.0,"minRowCount":1,"action":"warn","severity":"warn"}' '["SCHEMA","TABLE"]'
ensure_policy "dq_uniqueness_events" "Block duplicate event ids" \
  '{"maxDuplicateEventIds":0,"action":"block","severity":"critical"}' '["TABLE"]'

echo
echo "Attaching tags..."
attach_tag "schema" "iceberg.poc" "domain"
attach_tag "table" "iceberg.poc.snapshot_order" "dq_tier"
attach_tag "column" "iceberg.poc.events.payload" "pii"
attach_tag "topic" "kafka.default.domain-events" "domain"
attach_tag "topic" "kafka.default.domain-events" "freshness_class"

echo
echo "Attaching policies (direct + inherited)..."
attach_policy "schema" "iceberg.poc" "dq_completeness_order"
attach_policy "table" "iceberg.poc.snapshot_order" "dq_freshness_order"
attach_policy "table" "iceberg.poc.events" "dq_uniqueness_events"

verify() {
  local label="$1" path="$2"; shift 2
  local names
  names="$(names_at "${path}")"
  echo
  echo "=== ${label} ==="
  for expected in "$@"; do
    if printf '%s\n' "${names}" | grep -qx "${expected}"; then
      echo "  ${expected}: present"
    else
      echo "  ${expected}: MISSING" >&2
      exit 1
    fi
  done
}

verify "snapshot_order tags" "/api/metalakes/${METALAKE}/objects/table/iceberg.poc.snapshot_order/tags?details=true" \
  domain dq_tier
verify "snapshot_order policies" "/api/metalakes/${METALAKE}/objects/table/iceberg.poc.snapshot_order/policies?details=true" \
  dq_completeness_order dq_freshness_order
verify "events.payload column tags" "/api/metalakes/${METALAKE}/objects/column/iceberg.poc.events.payload/tags?details=true" \
  pii
verify "domain-events topic tags" "/api/metalakes/${METALAKE}/objects/topic/kafka.default.domain-events/tags?details=true" \
  domain freshness_class
verify "events table policies" "/api/metalakes/${METALAKE}/objects/table/iceberg.poc.events/policies?details=true" \
  dq_completeness_order dq_uniqueness_events

echo
echo "Tags and policies verified."

