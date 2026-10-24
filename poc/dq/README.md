# `dq/` — API data-quality execution (Python + Great Expectations)

> **Bounded code carve-out (D22).** `gx-dq-service/` is the only Python code home. It executes API
> response checks; it is not a catalog, an API gateway or a streaming engine.

## Responsibilities

- Consume redacted API response samples from Kafka `api-dq-samples` (async).
- Expose `POST /v1/validate` for critical/low-QPS synchronous checks.
- Load a GE suite by `asset_id + contract_version`.
- Convert JSON to a pandas DataFrame (`json_normalize`) or validate nested JSON with JSON Schema.
- Publish normalised results to Kafka `dq-results`.
- Optionally trigger GE Actions (Slack/Teams/custom webhook).

## Interfaces

| Interface | Direction | Purpose |
|---|---|---|
| `POST /v1/validate` | Spring → GE | sync validation (critical/low-QPS only) |
| `GET /health` | ops | readiness/liveness |
| Kafka `api-dq-samples` | Spring → GE | async samples (**planned**; POC uses `/v1/validate`) |
| Kafka `dq-results` | GE → Spring/writer | normalised results (**planned**) |

The implemented slice is `POST /v1/validate` with a JSON suite mounted from `poc/metadata/suites/`.
The Kafka worker is the production path and is not part of the current POC.

## Result contract

Each result maps to `poc.dq_results`:

| Field | Meaning |
|---|---|
| `run_id` | unique run |
| `asset_id` / `asset_type` | endpoint/table/topic |
| `contract_version` | suite/contract version |
| `check_name` | expectation name |
| `dimension` | freshness/completeness/validity/… |
| `status` | pass/warn/fail/error/unknown |
| `severity` | critical/warn |
| `observed_value` / `threshold` | evidence |
| `trace_id` | correlation with the API request |

## Execution policy

- **Async-first.** Full GE is not on the hot path.
- **Sync only** for critical/low-QPS endpoints, with timeout and circuit breaker.
- **No payload logging.** PII redaction/tokenization is planned for the Kafka sampling path.
- **No catalog writes.** Results go to Kafka; the writer persists to Iceberg through Trino.

## Why Python

GE is Python-only. It runs as a separate service (`gx-dq-service`), not embedded in the Spring JVM
(D20). A true sidecar is optional; a separate Deployment/service is the default.

## Related

- [`../docs/06-metadata-and-dq.md`](../docs/06-metadata-and-dq.md)
- [`../metadata/README.md`](../metadata/README.md)
- [`../../docs/decisions.md`](../../docs/decisions.md) — D18, D20, D22.
