# Goals & Objectives — Event Hub → Iceberg → Trino POC

**One vertical slice: prove domain events can travel Event Hub → object storage → Iceberg → catalog → Trino, with correct commit semantics and measurable freshness.**

---

## 1. Problem statement

Domain events are published by Event Hub (Kafka, JSON, domain-model payload). We need to know whether they can be landed as an **open Iceberg table** on object storage, catalogued by a **REST catalog**, and retrieved as an **aggregate snapshot** through Trino — without building any storage, catalog or query-engine machinery ourselves.

## 2. Goals

| # | Goal |
|---|---|
| **G1** | Prove the end-to-end path Kafka → Iceberg → catalog → Trino using **third-party components only** |
| **G2** | Prove retrieval of an **aggregate snapshot** keyed by `correlation_id` |
| **G3** | Prove the **catalog commit** is the atomicity boundary (no hand-written Iceberg metadata) |
| **G4** | **Measure** end-to-end freshness (the staleness budget) rather than assume it |
| **G5** | Establish a reusable **contract-first layer map** for the target platform |
| **G6** | Produce the **build-vs-buy / hot-view-vs-record decision** for the aggregate snapshot |

## 3. Objectives (measurable)

| # | Objective | Measure |
|---|---|---|
| **O1** | An event produced to Kafka is queryable in Trino within a bounded time | record seconds; break down into commit interval + metadata cache TTL |
| **O2** | A `correlation_id` query returns the correct stitched aggregate | all related events present, correctly ordered |
| **O3** | Restarting the sink produces no duplicates | row counts stable across restart |
| **O4** | Adding a payload field leaves old and new events readable | schema evolution verified |
| **O5** | Time travel returns an earlier table state | `FOR VERSION AS OF` matches expectation |
| **O6** | Zero hand-written Iceberg metadata in the repo | repository inspection |

## 4. Success criteria / KPIs

| KPI | Target |
|---|---|
| End-to-end visibility | ≤ commit interval + cache TTL (measured, stated) |
| Duplicate rows after restart | 0 |
| Aggregate reconstruction | 100 % of related events for the correlation id |
| Third-party reuse | 0 bespoke storage/catalog/query components |
| Reproducibility | `docker compose up` → working slice |

## 5. Non-goals (POC v1)

These are the **data-path** non-goals. POC v2 deliberately adds a bounded metadata/DQ/API control plane; see §13 for the POC v2 non-goals.

- Multi-engine (Spark/Flink), high availability, Keycloak/SSO.
- BigQuery interop, multi-cloud, cost optimisation.
- Governance, RBAC beyond the minimum needed to run.
- Compaction/snapshot-expiry automation.

## 6. Assumptions

- Kafka available (KRaft, single broker) and a topic can be created.
- MinIO exposes an S3-compatible endpoint.
- A REST catalog (Polaris) can be bootstrapped with a principal and a catalog.
- Trino runs with the Iceberg connector pointed at the REST catalog + MinIO.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Polaris bootstrap / RBAC friction | time-box; fall back to a simpler catalog, then swap (proves swappability) |
| Kafka Connect image packaging | build a custom Connect image with the Iceberg sink plugin |
| JSON type inference surprises | pin an explicit Iceberg table schema |
| Credential vending complexity | use static MinIO keys for the POC |

## 8. Traceability

| Requirement | Document | Artifact | Test |
|---|---|---|---|
| G1 | `01-architecture.md` | `infrastructure/` | T1 end-to-end |
| G2 | `01-architecture.md` | `sql/02_query_by_correlation.sql` | T2 aggregate |
| G3 | `01-architecture.md` §7 | `iceberg-sink.json` | **T7, T8** |
| G4 | `01-architecture.md` §10 | measured via CLI/SQL | T4 freshness |
| G5 | `01-architecture.md` §2 | layer READMEs | — |
| O3 | `01-architecture.md` §11 | — | T3 idempotency |
| O4 | `01-architecture.md` §4–§5 | — | T5 schema evolution |
| O5 | `01-architecture.md` §7 | — | T6 time travel |
| O6 | `01-architecture.md` §13–§14 | repository | **T9** |
| G6 | [`05-aggregation-bake-off.md`](05-aggregation-bake-off.md) | scorecard §4 | bake-off comparison |

## 9. Definition of done

All of O1–O6 pass, the slice runs from `docker compose`, and no bespoke iceberg/catalog/query code exists in the repository.

---

# POC v2 — control-plane extension

**POC v2 adds a metadata, contract, data-quality and API-enforcement slice around the proven data path.** The data path is unchanged; the control plane is additive.

## 10. Goals (POC v2)

| # | Goal |
|---|---|
| **G7** | Prove metadata federation across Kafka and Polaris/Iceberg **without copying metadata** |
| **G8** | Prove metadata-driven contracts/tags for **data and API assets**, plus policies for **data assets** |
| **G9** | Prove DQ execution across **Trino and operational APIs**, with unified results |
| **G10** | Prove **enforcement at the operational API boundary** with audit |
| **G11** | Produce the **Hybrid A vs Hybrid B decision**: is Gravitino + GE + Spring sufficient, or is OpenMetadata justified? |

## 11. Objectives (POC v2)

| # | Objective | Measure |
|---|---|---|
| **O7** | Gravitino lists `kafka.default.domain-events`, `iceberg.poc.events` and `iceberg.poc.snapshot_order`; a table created in Polaris appears without re-registration | metadata listing; no metadata copy |
| **O8** | Effective tags resolve at table/column/API-asset level; custom policies attach directly to objects and inherit down the hierarchy | tag/policy lookup evidence |
| **O9** | Data DQ detects injected duplicate, null, stale and reconciliation failures | failing checks; `dq_results`; Gravitino stats |
| **O10** | GE detects API response schema, range and uniqueness failures | failing GE checks; normalized results |
| **O11** | The Spring gate blocks critical fail/unknown, fails open standard, and emits `X-DQ-*` headers | gate scenario matrix; audit |
| **O12** | Measure inline, sync and async DQ overhead; the POC sync gate is measured at 0.35–0.89 s warm (12 s cold) | measured latency |
| **O13** | `docker compose up` reproduces the full POC v2; T1–T16 pass, T17 blocked | reproducibility evidence |

## 12. KPIs (POC v2)

| KPI | Target |
|---|---|
| Metadata coverage | 100 % of POC tables, topic and API endpoints in `asset_catalog` |
| Data DQ coverage | all critical checks (freshness, nulls, uniqueness, reconciliation) |
| API DQ coverage | schema, required fields, enums, ranges, uniqueness |
| Gate accuracy | 100 % of scripted scenarios match the endpoint-class policy |
| Request latency | inline <5 ms; POC sync GE measured **0.35–0.89 s warm** (12 s cold); async/cached target 0 ms |
| PII safety | no payloads in GE logs or audit; redaction verified |
| Regression | T1–T10 re-run after the Connect pause/control-state reset (currently blocked) |
| Reproducibility | `docker compose up` with `data` and `full` profiles |

## 13. Non-goals (POC v2)

- Replacing Polaris as the Iceberg catalog of record.
- Deploying OpenMetadata/DataHub in the POC.
- Kafka Schema Registry (unless **O12** resolves otherwise).
- Full cross-system/column-level lineage.
- HA, SSO, multi-region, cost optimisation.
- Data-masking/row-filter enforcement.
- Running full GE on every **high-QPS** request (the POC gate is synchronous for low-QPS validation).
- Blocking direct Trino queries (the API path is the enforcement path).
- Building a production-grade DQ platform.

## 14. Assumptions (POC v2)

- Gravitino 1.3.1 image is available and can use PostgreSQL.
- Polaris’s Iceberg REST endpoint is compatible with Gravitino’s REST catalog backend (to be spiked).
- The host has enough RAM for Gravitino + GE + Spring + existing JVMs (recommend 8–16 GB).
- Python 3.11/3.12 and Spring Boot 3.x/Java 21 are available.
- OpenAPI 3.1 is the API contract format.
- Kafka topics `api-dq-samples` and `dq-results` can be created.

## 15. Risks (POC v2)

| Risk | Mitigation |
|---|---|
| Gravitino → Polaris REST/OAuth/credential vending | time-boxed spike; fallback to metadata-only or catalog-swap experiment |
| 4 GB host cannot run the full stack | 8–16 GB or compose profiles; `GRAVITINO_MEM`, `GX_DQ_MEM`, `-Xmx` limits |
| Python/JVM operational split | separate `gx-dq-service`, health checks, pinned versions |
| GE latency on the request path | async-first; sync only critical/low-QPS; cache; circuit breaker |
| PII in API samples | redact/tokenize; allowlists; no payload logging; mTLS/OAuth |
| Contract/suite drift | version OpenAPI + GE suites with `contract_version`; T16 |
| Fail-open/closed ambiguity | per-endpoint policy table; explicit config; tests |
| Codeless constraint | bounded code carve-out (**D22**); code only in `operational-api/` and `dq/gx-service/` |
| Kafka schemas not in Gravitino | domain contract / Schema Registry; documented limitation |
| Partial lineage | optional OpenLineage; do not claim full API→table lineage |

## 16. Traceability (POC v2)

| Requirement | Document | Artifact | Test |
|---|---|---|---|
| G7 | `01-architecture.md` control plane; `06-metadata-and-dq.md` | `infrastructure/config/gravitino/` | T11 |
| G8 | `06-metadata-and-dq.md` | `metadata/api/openapi.yaml`, `asset_catalog` | T12 |
| G9 | `06-metadata-and-dq.md` | `sql/04`, `dq/gx-service/` | T13, T14 |
| G10 | `06-metadata-and-dq.md` | `operational-api/` | T15, T16 |
| G11 | [`06-metadata-and-dq.md`](06-metadata-and-dq.md) §13; [`05-aggregation-bake-off.md`](05-aggregation-bake-off.md); decisions | `RESULTS.md`, decision log | bake-off |

> **Artifact note:** these paths are implemented in POC v2; the wave result files record verification.

> **Wave status:** **O7 / T11 pass** ([`RESULTS-WAVE1.md`](../tests/RESULTS-WAVE1.md)); **O8 / T12 pass** ([`RESULTS-WAVE2.md`](../tests/RESULTS-WAVE2.md)); **O9 / T13 pass for data** ([`RESULTS-WAVE3.md`](../tests/RESULTS-WAVE3.md)); **O10 / T14, O11 / T15 and T16 pass** ([`RESULTS-WAVE4-5.md`](../tests/RESULTS-WAVE4-5.md)). T17 is **blocked** ([`RESULTS-T17.md`](../tests/RESULTS-T17.md)): the Connect task was paused and post-resume commits did not materialise rows; T6/T9 pass, T1/T7 partial. No payload logging; mTLS/PII sampling planned.

## 17. Definition of done (POC v2)

1. `docker compose up` reproduces the **data plane + control plane**.
2. Gravitino federates the Kafka topic and Polaris Iceberg tables **without copying metadata**.
3. Tags and custom DQ policies resolve at table/column level; API contracts resolve at endpoint level.
4. Data DQ checks produce deterministic `dq_results` and latest Gravitino statistics.
5. GE validates API responses; results are in `dq_results`; PII is redacted.
6. The Spring API gate enforces per endpoint class and exposes `X-DQ-*` headers.
7. Audit evidence exists for metadata access, gate decisions and DQ runs.
8. T1–T16 pass and T17 is blocked; the `RESULTS*.md` files record evidence and the remaining runtime/version remediation.
9. Docs and ADRs are updated; limitations and the Hybrid B production path are documented.
10. The decision instrument answers: **is Hybrid A sufficient, or is OpenMetadata worth the heavier footprint?**
