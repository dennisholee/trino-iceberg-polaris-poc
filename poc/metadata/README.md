# `metadata/` — contracts and DQ suite configuration

> **Configuration, not code.** This folder holds the API contract and the GE suite conventions used by
> the control plane. It does not contain a catalog, a DQ engine or executable application code.

## Contents

| Path | Purpose |
|---|---|
| `api/openapi.yaml` | Operational API contract (OpenAPI 3.1) |
| `suites/*.json` | Great Expectations suites mapped to `asset_id + contract_version` |
| `../sql/06_asset_catalog.sql` | DDL/seed for the unified asset index |

Data contracts are documented in [`../domain/README.md`](../domain/README.md); a separate
`contracts/*.yaml` registry is **not** part of this POC slice.

## Naming and versioning

- `asset_id`:
  - table: `iceberg.poc.snapshot_order`
  - topic: `kafka.default.domain-events`
  - API: `GET /v1/orders/{correlationId}`
- `contract_id`: stable logical name (`orders-api`, `snapshot-order`).
- `contract_version`: OpenAPI `info.version` (e.g. `orders-api-v1`).
- GE suite version **must** match `contract_version`; T16 verifies drift.

## `asset_catalog`

The unified index links data and API assets:

| Field | Example |
|---|---|
| `asset_id` | `GET /v1/orders/{correlationId}` |
| `asset_type` | `table` / `topic` / `api` |
| `contract_id` / `contract_version` | `orders-api` / `orders-api-v1` |
| `owner` / `domain` | `orders-team` / `orders` |
| `tags` | `pii`, `tier=gold` |
| `dq_status` | `pass`, `warn`, `fail`, `error`, `unknown`, `stale` |
| `last_run_at` | timestamp |

Gravitino is the source for data assets; OpenAPI is the source for API assets. `asset_catalog` is an
index, not a second catalog.

## PII and sampling

- Never commit payload samples or secrets.
- Redact/tokenize before sending samples to GE (planned for the Kafka path).
- Keep a per-suite field allowlist.
- Do not log payloads in the gate or the GE service.

## Related

- [`../docs/06-metadata-and-dq.md`](../docs/06-metadata-and-dq.md)
- [`../../docs/decisions.md`](../../docs/decisions.md) — D16–D27.
