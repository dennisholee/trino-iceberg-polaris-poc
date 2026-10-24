# `operational-api/` — Spring Boot API and DQ gate (PEP)

> **Bounded code carve-out (D22).** This is the operational API and the **policy enforcement point**.
> It reads from Trino, resolves contracts/DQ status, and allows/warns/blocks the response.

## Responsibilities

- Serve the aggregate read model: `GET /v1/orders/{correlationId}`.
- Run cheap inline validation (planned; the POC relies on GE).
- Use the configured asset/contract and call `ApiDqGate` (latest-status resolution is planned).
- Call `gx-dq-service` synchronously for low-QPS validation (**implemented**).
- Publish redacted samples to Kafka `api-dq-samples` (planned; production path).
- Consume `dq-results`, persist to `poc.dq_results` via Trino, refresh the cache (planned).
- Emit `X-DQ-*` headers and expose health (**implemented**); decision audit is planned.

## Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /v1/orders/{correlationId}` | operational aggregate read |
| `GET /internal/dq/status` | last gate decision |
| `GET /actuator/health` | health |
| `/actuator/prometheus` | planned (Micrometer is not enabled yet) |

## `ApiDqGate`

```java
public interface ApiDqGate {
    DqDecision evaluate(ApiDqRequest request);
}
```

| Implementation | Behaviour | Python? |
|---|---|---|
| `GxApiDqGate` | **implemented** — sync `POST /v1/validate` | Yes |
| `LocalJavaDqGate` | planned — Bean Validation / JSON Schema / OpenAPI | No |
| `GxCachedDqGate` | planned — cache + async samples | Indirect |
| `NoopDqGate` | tests/local only | No |

The current POC gate is synchronous and uncached for low-QPS validation. The
`?scenario=bad` query parameter is a test-only hook that injects an invalid order row.

## Decision policy

| Class | PASS | WARN | FAIL | ERROR/UNKNOWN/STALE |
|---|---|---|---|---|
| CRITICAL | 200 | 200 + warning | 503 | 503 |
| STANDARD | 200 | 200 + warning | 503 | 200 + warning |
| LOW_RISK | 200 | 200 + warning | 200 + warning | 200 + warning |

> The POC config uses `endpoint-class: CRITICAL`; only the fail-closed column is exercised. The
> STANDARD/LOW_RISK rows are the target matrix.

Headers implemented: `X-DQ-Status`, `X-DQ-Run-Id`, `X-Contract-Version`.
`X-Data-Freshness` is planned.

## Non-negotiables

- **No full GE on high-QPS requests.** The POC gate is synchronous for low-QPS validation; async/cache is the production target.
- **No payloads in logs**; redact/tokenize before sampling.
- **No Iceberg writes** except `dq_results` through Trino.
- **No silent pass** on `UNKNOWN`/`STALE`; policy is explicit per endpoint.
- **No direct Trino blocking**; the API path is the enforcement path.

## Tests

- Implemented evidence: T14/T15/T16 in [`../tests/RESULTS-WAVE4-5.md`](../tests/RESULTS-WAVE4-5.md).
- Planned: unit gate matrix, Kafka sample → GE → `dq-results` → cache, OpenAPI contract tests,
  full T1–T10 regression.

## Related

- [`../docs/06-metadata-and-dq.md`](../docs/06-metadata-and-dq.md)
- [`../dq/README.md`](../dq/README.md)
- [`../../docs/decisions.md`](../../docs/decisions.md) — D19, D22, D23.
