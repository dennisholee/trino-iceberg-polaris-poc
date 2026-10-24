#!/usr/bin/env bash
# Shared bootstrap helpers. Source this from the metadata/verify scripts.

POLARIS_URL="${POLARIS_URL:-http://localhost:8181}"
POLARIS_CLIENT_ID="${POLARIS_CLIENT_ID:-root}"
POLARIS_CLIENT_SECRET="${POLARIS_CLIENT_SECRET:-secret}"
POLARIS_SCOPE="${POLARIS_SCOPE:-PRINCIPAL_ROLE:ALL}"

polaris_token() {
  local token
  token="$(curl -sS -X POST "${POLARIS_URL}/api/catalog/v1/oauth/tokens" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=client_credentials' \
    --data-urlencode "client_id=${POLARIS_CLIENT_ID}" \
    --data-urlencode "client_secret=${POLARIS_CLIENT_SECRET}" \
    --data-urlencode "scope=${POLARIS_SCOPE}" | jq -r '.access_token // empty')"
  if [ -z "${token}" ]; then
    echo "Failed to obtain a Polaris token from ${POLARIS_URL}" >&2
    return 1
  fi
  printf '%s' "${token}"
}
