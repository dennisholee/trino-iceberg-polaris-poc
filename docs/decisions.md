# Decision Log (ADR set)

**Consolidated record of the decisions made across the architecture documents and the POC.** Each entry states the decision, why, and its status. Open items are listed at the end.

---

## Accepted

| ID | Decision | Rationale | Status |
|---|---|---|---|
| **D1** | The **invariant is the open table-format + REST-catalog contract** (Iceberg + a REST catalog). **Trino is the default engine**, not the constant. | keeps portability while allowing any engine; resolves the "open vs engine-centric" contradiction | ✅ accepted |
| **D2** | Realise the slice **config-defined ("codeless")**; no application code. | reuses third-party components; keeps the POC about architecture, not software | ✅ accepted *(extended by D22 for POC v2)* |
| **D3** | Fold default is **S2 (Trino `MERGE`)**; the **fold engine is pluggable**. | fewest moving parts; the snapshot table is the contract | ✅ accepted |
| **D4** | The **event log is the source of truth**; snapshots are derived and disposable. | enables replay, correction and rebuild | ✅ accepted |
| **D5** | **BigQuery is an optional on-ramp/intermediate**, not the target. | avoids re-acquiring the lock-in the design exists to escape | ✅ accepted |
| **D6** | **Freshness is a measured SLO**, not an assumption. | staleness = commit + cache TTL + planning | ✅ accepted |
| **D7** | POC write path is the **Iceberg Kafka Connect sink** (the catalog owns the commit). | mature, supported; no hand-rolled metadata | ✅ accepted |
| **D8** | Catalog is **Polaris**, swappable via the Iceberg REST spec. | open, self-hostable, standard protocol | ✅ accepted |
| **D9** | Framing is **Contracts & Bindings** (contract-first); `domain/`·`application/`·`adapters/` are **documentation-only**. | the slice is codeless; "clean architecture" as code layering would be a category error | ✅ accepted *(supersedes the original clean-architecture framing)* |
| **D10** | **Codeless carve-out:** a thin **test harness** (SQL/shell) is the only permitted code. | enables verification without breaking D2 | ✅ accepted *(extended by D22 for POC v2)* |
| **D11** | The POC is a **decision instrument**, not a demo: it must answer **hot-view vs record** and **build vs buy** (objective G6). | the plumbing is commodity; the decision is not | ✅ accepted |
| **D12** | Object-store binding = **`bitnamilegacy/minio:latest`**. | MinIO's community images were **removed from Docker Hub** (2025). Bitnami's legacy repo publishes the same server; the S3-API contract is unchanged. | ✅ accepted (2025-10) |
| **D13** | The Iceberg Kafka Connect sink must be **built from Iceberg source** (Gradle), not pulled. | **No binary is published** — not on Docker Hub, Maven Central, GitHub releases, or the Apache dist. The docs state the connector zip is produced by the Iceberg build. | ✅ accepted (2025-10) — **validated**: see the recipe below |
| **D14** | The Polaris metastore is **`relational-jdbc` on Postgres**, never the default `in-memory`. | `in-memory` is **test-only** — it loses every catalog, namespace, table and principal on restart, and the server logs a readiness warning. The schema must be pre-created (Polaris does not create it) and the realm bootstrapped once with the **Admin Tool**. | ✅ accepted (2025-10), verified: catalogs survive a restart |
| **D15** | Polaris mints tokens with a **stable, mounted RSA key pair**. | By default Polaris generates an **ephemeral** key pair at every start, so every previously issued token is rejected — any long-lived client breaks on restart. Observed directly: the Kafka sink failed with `NotAuthorizedException: Failed to verify the token` after a Polaris restart. | ✅ accepted (2025-10), verified: a pre-restart token still validates after restart |
| **D16** | **Gravitino is a metadata/control plane beside Polaris**, not a catalog replacement. Polaris remains the Iceberg catalog of record. | Preserves **D8** and the proven commit path; Gravitino federates live metadata without copying it; no need to re-prove Iceberg atomicity. | ✅ accepted (2026-10) — POC v2 |
| **D17** | **POC v2 uses Hybrid A:** Gravitino + OpenAPI registry + Trino SQL/GE + Iceberg `dq_results` + Spring API gate. | Fits the current footprint, keeps the data path unchanged, and isolates the new capability. **Hybrid B (OpenMetadata)** is the production evaluation path. | ✅ accepted (2026-10) — POC v2 |
| **D18** | DQ execution is split: **Trino SQL for data**, **Great Expectations for API responses**; both write to one `dq_results` model. | SQL is native to Trino; GE is strongest for DataFrame/API payloads; a common results schema makes the gate simple. **POC persists the Trino data run; API result persistence is deferred to the async `dq-results` consumer.** | ✅ accepted (2026-10) — POC v2 |
| **D19** | The **operational API gate is the policy enforcement point (PEP)**. Gravitino, GE and OpenMetadata do not block API responses natively. | Gravitino custom policies are not enforced; GE is an execution engine; OpenMetadata contracts check schema/semantics, not runtime responses. | ✅ accepted (2026-10) — POC v2 |
| **D20** | GE runs as a **separate Python service** (`gx-dq-service`), not embedded in the JVM. **Async-first**; sync only for critical/low-QPS endpoints. | GE is Python-only; per-request GE is too slow for hot APIs; a separate service isolates runtime and scaling. | ✅ accepted (2026-10) — POC v2 |
| **D21** | `dq_results` history lives in **Iceberg**; latest status is cached and optionally mirrored to Gravitino `custom.dq.*` statistics. | Gravitino statistics are not a time series; Iceberg provides history and time travel. | ✅ accepted (2026-10) — POC v2 |
| **D22** | **Code carve-out:** the Spring operational API and Python GE service are permitted code. The original data path remains codeless. | API enforcement and GE integration cannot be done codeless; the carve-out is confined to `operational-api/` and `dq/gx-service/`. **Extends D2/D10; does not supersede them.** | ✅ accepted (2026-10) — POC v2 |
| **D23** | Fail-open/fail-closed is **per endpoint class** (critical / standard / low-risk), not global. | A single global policy is unsafe; payments/risk APIs should fail closed, analytics/low-risk APIs can fail open with a warning. **POC implements the CRITICAL path; STANDARD/LOW_RISK are target policy.** | ✅ accepted (2026-10) — POC v2 |
| **D24** | Kafka payload schemas remain in the **domain contract** (or a Schema Registry). Gravitino’s Kafka catalog registers **topic metadata only**. | Gravitino does not capture message schemas; setting that expectation prevents a false gap. | ✅ accepted (2026-10) — POC v2 |
| **D25** | After the POC, evaluate **OpenMetadata (Hybrid B)** as the production path if unified tables/topics/APIs/contracts/incidents justify the heavier footprint. | OpenMetadata covers tables, topics, API endpoints, contracts, native table DQ and incidents; it is materially heavier. The POC must produce the evidence for that decision. | ✅ accepted (2026-10) — POC v2 |
| **D26** | Gravitino → Polaris uses **caller Bearer-token passthrough**. The POC adds a **spike-only** `PolarisTokenValidator` because Polaris JWTs have no `aud` claim; production must use audience-bound tokens from an IdP/token broker. | Gravitino's REST backend forces `UserPrincipalForwardingAuthManager`; static catalog credentials are ignored. Polaris' built-in validator requires an audience. The shim makes the federation spike work without pretending it is production auth. | ✅ accepted (2026-10) — POC v2 |
| **D27** | POC v2 uses the **Gravitino 1.3.1 policy model**: tags classify; **policies attach directly to objects** and inherit down the hierarchy. Tag-to-policy association/selectors are deferred. | In 1.3.1, custom policies are attached to catalogs/schemas/tables/topics and inherit to descendants; `TAG_VALUE` selectors are a newer feature. The POC gate enforces the configured GE suite; Gravitino policy resolution in the request path is not implemented. | ✅ accepted (2026-10) — POC v2 |
| **D28** | The browser-facing Polaris endpoint on **8181** is a small **nginx facade** (`polaris-proxy`); Polaris itself stays on `polaris:8181` inside the compose network (host **8182** for debugging). | The Gravitino UI sends its global `Accept: application/vnd.gravitino.v1+json` to the token endpoint and Polaris produces only `application/json` → **406**. The facade rewrites `Accept` for that one path and supplies CORS for `http://localhost:8090`; internal Trino/Gravitino/Connect clients are unchanged. | ✅ accepted (2026-10), verified: browser login reaches `/ui/metalakes` |

> **D22 extends D2 and D10 rather than superseding them:** the data path remains codeless; the operational API and GE service are a bounded code carve-out. No existing decision is superseded.

### D13 in practice — the validated build recipe

```
stage 1  gradle:8.14.5-jdk21
         curl apache-iceberg-1.12.0.tar.gz  (dlcdn.apache.org)
         gradle --no-daemon --max-workers=2 -x test -x integrationTest \
           :iceberg-kafka-connect:iceberg-kafka-connect-runtime:build
         → kafka-connect/kafka-connect-runtime/build/distributions/iceberg-kafka-connect-runtime-1.12.0.zip
stage 2  confluentinc/cp-kafka-connect:8.0.0   (Java 17 — 7.x is Java 11 and rejects the classes)
         extract the non-hive zip, flatten lib/*.jar into a plugin directory
```

Three constraints are load-bearing: the **Gradle project is renamed** in `settings.gradle` (the path is `:iceberg-kafka-connect:iceberg-kafka-connect-runtime`, not `…:kafka-connect-runtime`); the worker needs **Java 17+**; and the connector must be **on the worker's plugin path** (`/etc/kafka-connect/kafka-connect.properties`). Build time was ~6.5 min and it OOM'd at 4 GB of RAM until the other JVMs were stopped.

## Open

| ID | Question | Default if undecided |
|---|---|---|
| **O1** | How are events produced for the POC? | Connect source connector / `kcat` CLI |
| **O2** | Fold engine for the POC? | Trino SQL |
| **O3** | `payload` typing? | explicit typed columns via DDL |
| **O4** | Scheduler for the periodic `MERGE`? | `cron` / Trino scheduled query |
| **O5** | ~~Catalog fallback if Polaris bootstrap blocks?~~ **Resolved — not needed.** Polaris bootstrap is reliable once the schema pre-exists and the metastore is JDBC (**D14**/**D15**); the fallback is retained only as a note. | simpler REST/JDBC catalog, then swap back |
| **O6** | Orchestration-evidence scope? | **T7–T9 required**, T10 optional |
| **O7** | Managed vs self-hosted for the real deployment? | evaluate per `alternative-architectures.md` §4–§5 |
| **O8** | API DQ engine: GE vs Java-native validators vs OpenMetadata DataFrameValidator? | GE for the POC; Java-native inline checks for hot paths |
| **O9** | API enforcement shape: Spring gate vs API gateway + OPA vs sidecar? | Spring `ApiDqGate` for the POC |
| **O10** | Production metadata plane: Gravitino vs OpenMetadata vs DataHub? | Gravitino for POC; OpenMetadata for Hybrid B evaluation |
| **O11** | Sync GE latency budget and sampling rate? | Async-first; sync <200 ms p95 target; POC measured 0.35–0.89 s warm |
| **O12** | Is a Kafka Schema Registry in scope? | No; domain contract remains the schema source |
| **O13** | Lineage scope: OpenLineage/Marquez now, or defer? | Defer; optional log sink in POC v2 |
| **O14** | Production authentication for Gravitino → Polaris? | Use an IdP/token broker with audience-bound tokens; do not ship `PolarisTokenValidator` |
| **O15** | Kafka Connect task reports `RUNNING` while its target state is `PAUSED`, and post-resume commits can be empty: how should the runbook reset and verify it? | Always `PUT /resume`, assert lag drains, reset connector/control state, investigate the coordinator, then rerun T1–T10 |

## Superseded

| Supersedes | By | Reason |
|---|---|---|
| "Trino is the constant" | **D1** | conflated engine with contract |
| "Clean architecture layering (code)" | **D9** | no code exists in a codeless slice |

## How to use

- A decision is only **accepted** when its rationale is recorded here and it is referenced from the affected document.
- Changing an accepted decision requires a **new entry** that names what it supersedes.
- **Open** items must be resolved before the wave that depends on them, or explicitly deferred with a recorded default. POC v2 open items (O8–O15) are tracked per wave.
