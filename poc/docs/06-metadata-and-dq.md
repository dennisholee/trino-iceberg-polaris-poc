# POC v2 — Metadata, Contracts, Data Quality and the API Gate

**POC v2 adds a metadata/contract/DQ control plane around the proven data path.** It does not replace Polaris, Trino, the Connect sink or the event contract.

Decisions: **D16–D27** in [`../../docs/decisions.md`](../../docs/decisions.md). Options comparison: [`../../docs/metadata-and-data-quality-options.md`](../../docs/metadata-and-data-quality-options.md).

---

## 1. Scope

| In scope | Out of scope |
|---|---|
| Gravitino federation of Kafka topic + Polaris Iceberg tables | Replacing Polaris |
| Tags, custom policies (semantic model/statistics planned) | Full OpenMetadata/DataHub deployment |
| OpenAPI contract registry + `asset_catalog` | Kafka Schema Registry |
| Trino SQL data DQ + GE API DQ | Full cross-system lineage |
| Spring API gate (PEP) + headers (decision audit planned) | HA/SSO/data-masking enforcement |
| Iceberg `dq_results` history | Full GE on high-QPS requests (POC gate is sync/low-QPS) |

**Code carve-out (D22):** only `operational-api/` and `dq/gx-service/` contain code. The data path remains codeless.

---

## 2. Architecture

```text
┌──────────────────────────────────────────────────────────────┐
│ Spring operational API — ApiDqGate (PEP)                     │
│  inline Java validation · cached status · async/sync GE      │
│  decision: 200 / headers / 503 · audit (planned)             │
└───────────────┬──────────────────────────────┬───────────────┘
                │ OpenAPI contract            │ Trino SQL
                ▼                              ▼
┌──────────────────────────────────┐   ┌────────────────────────┐
│ Gravitino + OpenAPI registry    │   │ Trino                  │
│  Kafka topic · Polaris tables   │   │  events · snapshot     │
│  tags · policies · statistics   │   │  dq_results            │
│  audit · semantic model         │   │                        │
└───────────────┬──────────────────┘   └──────────▲─────────────┘
                │                                 │
         Kafka/Polaris                    Kafka dq-results
                │                                 │
                └──────────────┬──────────────────┘
                               ▼
                  ┌──────────────────────────────┐
                  │ gx-dq-service (Python + GE)  │
                  │ FastAPI /v1/validate         │
                  │ Kafka api-dq-samples         │
                  │ suites per asset/contract    │
                  └──────────────────────────────┘
```

> **POC slice vs target:** the diagram shows the target control plane. The implemented slice is the
> sync GE gate (CRITICAL), Gravitino tags/policies, and Trino data DQ; inline/cache/async Kafka,
> statistics, semantic model and gate audit are target/planned.

The data path is unchanged:

```text
Event Hub ─▶ Kafka ─▶ Connect Iceberg sink ─▶ MinIO ─▶ Polaris ─▶ Trino
```

---

## 3. Components

| Component | Role | Product | In data path? |
|---|---|---|---|
| Gravitino | metadata federation, tags/policies/statistics/audit | Apache Gravitino | No |
| OpenAPI registry | API contract source | Git / OpenAPI 3.1 | No |
| `gx-dq-service` | API response DQ | Great Expectations | No |
| `operational-api` | API + enforcement (PEP) | Spring Boot | Read path |
| `dq_results` | DQ history | Iceberg/Trino | Evidence |
| Cache | latest DQ status | Caffeine (Redis optional) | No |
| `api-dq-samples` / `dq-results` | async DQ flow | Kafka | No |

**Key rule:** Gravitino, GE and the OpenAPI registry are **control/evidence planes**. The Spring API is the only **policy enforcement point**.

---

## 4. Metadata model

### 4.1 Gravitino

- Metalake `poc`.
- `kafka` catalog → topic `domain-events` (metadata only; **no payload schemas**, D24).
- `iceberg` catalog with `catalog-backend=rest` → Polaris `/api/catalog`, warehouse `poc`.
- Tags: `domain`, `pii`, `dq_tier`, `freshness_class`, `api_exposure`.
- Custom DQ policies: freshness, completeness, uniqueness (reconciliation is a Trino check).
- **Version note (Gravitino 1.3.1):** policies attach **directly to objects** (catalog/schema/table/topic) and inherit down the hierarchy. Tag-to-policy association and `TAG_VALUE` selectors are a newer Gravitino feature and are **not** used in this POC. Tags classify; policies prescribe (**D27**).
- Semantic model `order_snapshot` on `iceberg.poc.snapshot_order` (**planned**).
- Latest table-level `custom.dq.*` statistics (**planned**, D21).

Gravitino **federates**; it does not copy metadata. A table created in Polaris appears without re-registration.

### 4.2 OpenAPI registry

- `metadata/api/openapi.yaml` is the API contract source.
- `asset_id` = `METHOD /path` (e.g. `GET /v1/orders/{correlationId}`).
- `contract_version` = OpenAPI `info.version`.
- GE suite name and version must match `contract_version`.

### 4.3 `asset_catalog`

| Field | Example |
|---|---|
| `asset_id` | `iceberg.poc.snapshot_order` / `GET /v1/orders/{correlationId}` |
| `asset_type` | `table` / `topic` / `api` |
| `name` | Human-readable |
| `owner` / `domain` | `orders-team` / `orders` |
| `tags` | `pii`, `tier=gold` |
| `contract_id` / `contract_version` | `snapshot-order-v1` / `orders-api-v1` |
| `dq_status` | `pass`, `warn`, `fail`, `error`, `unknown`, `stale` |
| `last_run_at` | timestamp |
| `lineage_ref` | OpenLineage run ID |

In the POC, `06_asset_catalog.sql` upserts a **fixed demo index**. A metadata-sync job that reads
Gravitino assets and the OpenAPI spec is the production target. It is an **index**, not a second catalog.

### 4.4 Authentication note (Wave 1 finding)

Gravitino's `lakehouse-iceberg` REST backend uses `UserPrincipalForwardingAuthManager`: it forwards the **caller's Bearer token** to Polaris. As a result:

- Anonymous/simple calls fail with `NotAuthorizedException`.
- Static `gravitino.bypass.credential` / `scope` catalog properties are overwritten by the forwarding auth manager.
- The bootstrap scripts obtain a Polaris token (`client_credentials`) and send `Authorization: Bearer <token>` to Gravitino.

Polaris JWTs have **no `aud` claim**, so Gravitino's built-in `StaticSignKeyValidator` rejects them. The POC image adds a **spike-only** `PolarisTokenValidator` that verifies the RS256 signature, issuer `polaris` and the `active` claim. This is not a production authentication design; production should use an IdP/token broker with audience-bound tokens (**D26**).

---

## 5. Contract model

| Section | Data table | Kafka topic | API endpoint |
|---|---|---|---|
| Schema | Columns/types | Event envelope + Schema Registry | OpenAPI request/response |
| Semantics | Keys/relationships | Envelope invariants | Idempotency, pagination, status |
| Quality | Freshness, nulls, uniqueness, reconciliation | Envelope validity/ordering | Schema, enums, ranges, uniqueness, latency |
| SLA | Freshness target | Event lag target | p95 latency, availability, error budget |
| Security | Classification, row filters | PII classification | AuthN/AuthZ, PII redaction |
| Terms | Usage terms | Usage terms | Consumer terms |

Contracts are versioned. A contract change requires a matching suite change (T16).

---

## 6. DQ model (D18)

### 6.1 Data checks (Trino SQL)

- `event_id` uniqueness
- null `aggregate_id` / `correlation_id` / `seq` / `occurred_at`
- `seq` monotonic per aggregate
- snapshot `version` vs max event `seq`
- correlation completeness
- freshness lag (`now - max(occurred_at)`)
- snapshot freshness (`now - watermark_at`)

### 6.2 API checks (GE)

- required fields / non-null
- types, formats, enums
- ranges (total ≥ 0, percentages)
- uniqueness (`order_id`)
- row count bounds
- cross-field consistency
- response shape vs OpenAPI
- latency / error rate (synthetic or gate-level)
- tenant/authz isolation (security test)
- PII redaction check

### 6.3 Execution patterns

| Pattern | When | Request impact |
|---|---|---|
| **Inline Java validation** | every request | <5 ms; schema/required/range checks |
| **Async GE sampling** | hot APIs | none; results eventually consistent |
| **Sync GE** | critical/low-QPS only | GE ~25–40 ms warm; full API ~0.35–0.89 s warm |
| **Synthetic checks** | continuous monitoring | none; scheduled API calls |

**Rule:** in production, full GE is **not** run on every high-QPS request. The POC gate is synchronous for low-QPS validation; async sampling is the production target.

### 6.4 `dq_results`

```sql
CREATE TABLE poc.dq_results (
  run_id           varchar,
  asset_id         varchar,
  asset_type       varchar,   -- table | topic | api
  contract_id      varchar,
  contract_version varchar,
  check_name       varchar,
  dimension        varchar,
  status           varchar,   -- pass | warn | fail | error | unknown
  severity         varchar,   -- critical | warn
  observed_value   varchar,
  threshold        varchar,
  details          varchar,   -- JSON
  trace_id         varchar,
  run_at           timestamp(6) with time zone
)
WITH (partitioning = ARRAY['day(run_at)']);
```

History lives in Iceberg; latest status is cached and optionally mirrored to Gravitino `custom.dq.*` statistics (**D21**). Gravitino statistics are **not** a time series.

---

## 7. Enforcement model (D19, D23)

### 7.1 Endpoint classes

| Class | Examples | Default |
|---|---|---|
| **CRITICAL** | payments, risk, regulatory | fail-closed |
| **STANDARD** | order/account reads | block on data failure; fail-open on unknown |
| **LOW_RISK** | analytics, internal read-only | warn only |

### 7.2 Decision matrix

| Class | PASS | WARN | FAIL | ERROR / UNKNOWN / STALE |
|---|---|---|---|---|
| **CRITICAL** | `200` | `200` + warning | `503` | `503` |
| **STANDARD** | `200` | `200` + warning | `503` | `200` + warning |
| **LOW_RISK** | `200` | `200` + warning | `200` + warning | `200` + warning |

Distinguish **data failure** (`FAIL`) from **system failure** (`ERROR`, `UNKNOWN`, `STALE`). A GE outage must not look like `PASS`.

> **POC scope:** the single `orders` endpoint is configured `endpoint-class: CRITICAL` and exercises the
> fail-closed column. The STANDARD/LOW_RISK matrix is the target policy; only CRITICAL is tested in
> this slice. `WARN` is defined but the current GE suite emits `pass`/`fail` only.

### 7.3 Headers

```text
X-DQ-Status: pass|warn|fail|unknown|stale
X-DQ-Run-Id: <run_id>
X-Contract-Version: orders-api-v1
X-Data-Freshness: 2026-10-17T10:15:00Z
```

### 7.4 Direct Trino users

The API path is the enforcement point. Direct Trino users are governed by Trino access control plus alerts/contracts; the POC does not block ad-hoc SQL.

---

## 8. Spring integration

### 8.1 Gate abstraction

```java
public interface ApiDqGate {
    DqDecision evaluate(ApiDqRequest request);
}
```

Implementations:

| Implementation | Behaviour | Python? |
|---|---|---|
| `GxApiDqGate` | **implemented** — sync call to `gx-dq-service` | Yes |
| `LocalJavaDqGate` | planned — Bean Validation / JSON Schema / OpenAPI | No |
| `GxCachedDqGate` | planned — latest status cache + async samples | Yes, indirectly |
| `NoopDqGate` | tests/local only | No |

### 8.2 Request flow

1. Controller returns the response DTO.
2. Inline Java validation (cheap checks) — **planned**; the POC relies on GE for validation.
3. `ApiDqGate` uses the configured contract and calls GE (latest-status lookup is planned).
4. For hot APIs: publish a redacted sample to `api-dq-samples`; enforce from cache.
5. For critical/low-QPS: optional sync `POST /v1/validate` with timeout/circuit breaker.
6. Emit `X-DQ-*` headers; audit the decision (**planned**); update Micrometer metrics (**planned**).

> **Wave 4–5 implementation note:** the POC gate calls GE **synchronously** for low-QPS validation
> (`GxApiDqGate`). Measured end-to-end: **0.35–0.89 s warm**, **12 s cold**; GE direct is ~25–40 ms
> warm. Async Kafka sampling and `GxCachedDqGate` remain the production target. The
> `?scenario=bad` query parameter is a test-only hook, not part of the public contract.

### 8.3 Cache and results

- Caffeine cache keyed by `asset_id + contract_version` (planned; the POC gate is uncached).
- TTL 30–60 s (configurable).
- `dq-results` consumer writes to `dq_results` through Trino and refreshes the cache (planned).
- Redis optional for multi-instance deployments.

### 8.4 Failure semantics

- GE timeout/circuit open → `UNKNOWN`; policy decides.
- Cache stale → `STALE` (**planned**; the POC gate is uncached).
- Invalid suite/validation error → `UNKNOWN` in the POC (fail-closed); a distinct `ERROR` is a future refinement.
- Do not silently pass on any of the above.

---

## 9. GE service

- Python + FastAPI + Great Expectations + pandas.
- `POST /v1/validate` for sync checks.
- Kafka consumer on `api-dq-samples` for async checks (planned; POC uses `/v1/validate`).
- Kafka producer on `dq-results` (planned).
- Suites loaded from `poc/metadata/suites/` by `asset_id + contract_version`.
- `json_normalize` for tabular responses; JSON Schema validation for nested structures.
- No payload logging; redaction/tokenization is planned for the Kafka sampling path.
- mTLS/OAuth between Spring and GE is planned; GE is not externally exposed.

**Why not embedded:** GE is Python-only; a separate service isolates runtime, scaling and upgrades (D20). A true sidecar is optional but not the default; a separate Deployment/service is preferred.

---

## 10. Deployment

### 10.1 Services and ports

| Service | Port | Profile |
|---|---|---|
| Kafka / MinIO / Postgres / Polaris / Trino / Connect | existing | `data` |
| Gravitino | 8090 | `full` |
| `gx-dq-service` | 8000 | `full` |
| `operational-api` | 8082 | `full` |
| Prometheus / Grafana (optional) | 9090 / 3000 | `full` |

### 10.2 Run order

1. `docker compose --profile data up -d`; bootstrap Polaris; create tables; register the sink; produce/fold.
2. Ensure the Gravitino PostgreSQL schema exists (`00-init-db.sh`) and start Gravitino.
3. Bootstrap Gravitino: metalake `poc`, `kafka` catalog, `iceberg` catalog (`catalog-backend=rest` → Polaris). The scripts obtain a Polaris bearer token and pass it to Gravitino.
4. Create tags/policies (`03-tags-policies.sh`); create the semantic model (later).
5. Create `dq_results` and `asset_catalog` (`05`, `06`). If the raw `events` table is empty, run `08_seed_events_from_sink.sql`; rebuild the snapshot (`03`); run data DQ (`04`); refresh asset status (`07`).
6. Push latest `custom.dq.*` statistics to Gravitino (planned).
7. Start `gx-dq-service` and `operational-api`.
8. Call the gate and run T14–T16. T17 is **blocked** by a paused Connect task plus an empty post-resume commit; see `../tests/RESULTS-T17.md`. The POC validates synchronously; async sample publication is planned.

### 10.3 Memory and security

- Full profile requires **8–16 GB**; 4 GB is insufficient.
- Gravitino uses a separate Postgres database/schema and the official schema script.
- GE and Spring communicate over the compose network; mTLS/OAuth is **planned**. GE is not externally exposed.
- API payloads are **not logged**; sampling/redaction is **planned** for the Kafka path.

---

## 11. Verification

| Test | Evidence |
|---|---|
| T11 metadata federation | Gravitino lists Kafka topic + Polaris tables; Polaris-created table appears; no copy |
| T12 tags/policies | effective tags and direct/inherited policies at table/column/API |
| T13 data DQ | checks execute; stale seed fails; `dq_results`; asset status (Gravitino stats deferred) |
| T14 API DQ | GE detects schema/range/uniqueness failures; normalized results |
| T15 API gate | critical blocks; headers; last decision (audit deferred) |
| T16 contract drift | unknown suite/version → 404; gate fails closed |
| T17 regression/security | **blocked** — paused task + empty post-resume commit; T6/T9 pass, T1/T7 partial; no payload logging; mTLS/PII planned |

Measured: GE direct ~25–40 ms warm; the Spring API end-to-end is **0.35–0.89 s warm** and **12 s cold**
(first request, Trino/Hikari/GE warm-up). The async/cache production target is 0 ms added.

---

## 12. Limitations

| Limitation | Consequence |
|---|---|
| Gravitino has no API-endpoint entity | OpenAPI registry + `asset_catalog` bridge API assets |
| Gravitino has no DQ engine | Trino SQL/GE execute; Gravitino stores metadata/latest stats |
| Gravitino custom policies are not enforced | the Spring gate evaluates them |
| GE is Python-only | separate `gx-dq-service`; not embedded in the JVM |
| GE is batch/DataFrame-oriented | sampling/checkpoints, not per-event streaming |
| Kafka schemas are not in Gravitino | domain contract/Schema Registry remains the source |
| Statistics are not history | `dq_results` is the history |
| Lineage is partial | OpenLineage optional; no full API→table lineage claim |
| Polaris JWTs have no `aud` claim | POC uses a spike-only validator; production needs audience-bound tokens (**D26**) |
| Gravitino 1.3.1 policies are direct object attachments | no tag selectors; policies are metadata-only in the POC; the gate enforces the configured GE suite (**D19/D27**) |
| POC gate is synchronous and uncached | measured 0.35–0.89 s warm (12 s cold); async Kafka sampling and Caffeine cache are planned |
| API DQ evidence is not yet in `dq_results` | the gate returns `X-DQ-Run-Id`; the async `dq-results` consumer will persist it |

---

## 13. Production path

If the POC shows that unified metadata/contracts/incidents justify the heavier footprint, evaluate **Hybrid B**:

- **OpenMetadata** for tables, topics, API endpoints, contracts, native table DQ and incidents.
- Trino for Iceberg DQ execution.
- GE/DataFrame runner for API response checks.
- API gateway/OPA or a Spring decision service for enforcement.
- OpenLineage for lineage.
- Kafka Schema Registry for payload schemas.

This is **D25**; it is not part of the POC.

**G11 decision evidence from this POC:** live federation (T11), tag/policy inheritance (T12),
data and API DQ (T13/T14), and a synchronous gate at **0.35–0.89 s warm** (T15). Coverage gaps are
OpenMetadata-native API entities, incidents and lineage; the POC footprint adds Gravitino, GE and
the Spring API plus a Postgres schema.

---

## 14. References

- [`../../docs/decisions.md`](../../docs/decisions.md) — D16–D27, O8–O15.
- [`00-goals-and-objectives.md`](00-goals-and-objectives.md) — G7–G11, O7–O13.
- [`01-architecture.md`](01-architecture.md) — control-plane architecture.
- [`03-third-party-services.md`](03-third-party-services.md) — reuse register and limits.
- [`04-architecture-practices.md`](04-architecture-practices.md) — practices/anti-patterns.
- [`../../docs/metadata-and-data-quality-options.md`](../../docs/metadata-and-data-quality-options.md) — options/hybrids.
- [`../tests/RESULTS-WAVE1.md`](../tests/RESULTS-WAVE1.md) — metadata federation + OAuth finding.
- [`../tests/RESULTS-WAVE2.md`](../tests/RESULTS-WAVE2.md) — tags/policies + policy model finding.
- [`../tests/RESULTS-WAVE3.md`](../tests/RESULTS-WAVE3.md) — asset catalog + data DQ evidence.
- [`../tests/RESULTS-WAVE4-5.md`](../tests/RESULTS-WAVE4-5.md) — GE API DQ + Spring gate evidence.
- [`diagrams/seq-06-metadata-federation.svg`](diagrams/seq-06-metadata-federation.svg)
- [`diagrams/seq-07-dq-gate.svg`](diagrams/seq-07-dq-gate.svg)