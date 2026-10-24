# Architecture Practices — What This POC Adopts

**The current (2025–2026) practices this slice is deliberately built around.**

---

| # | Practice | How it shows up here |
|---|---|---|
| 1 | **Open table format + REST catalog** | Iceberg tables on MinIO, catalogued by Polaris over the Iceberg REST spec — portable by design |
| 2 | **Event sourcing / log as source of truth** | `events` is immutable; the snapshot is a derived, replayable fold |
| 3 | **Contract-first layering (codeless)** | contracts → capabilities → bindings → runtime; artefacts reference contracts, never internals |
| 4 | **Config-over-code integration** | the Kafka→Iceberg writer is a **connector config**, not a program |
| 5 | **Walking skeleton / vertical slice** | thinnest path through every layer end-to-end before any depth |
| 6 | **Reuse over rebuild** | see `03-third-party-services.md`; a reuse register with a hard rule |
| 7 | **Contract-first data** | the event envelope is the contract; `schema_version` + registry rules |
| 8 | **Reproducible local environments** | `docker compose up` reproduces the whole slice |
| 9 | **Testcontainers integration testing** | tests exercise the real Kafka/MinIO/Trino boundaries |
| 10 | **Measure, don't assume** | freshness is an SLO measured per objective O1, not an estimate |
| 11 | **Idempotent, replayable pipelines** | `seq > version` guard; offset resets are safe |
| 12 | **Observable by default** | structured logs and snapshot metadata (`$snapshots`) for inspection |
| 13 | **AI-assisted / agentic development** | persona-driven agent workflow (`02-agent-driven-development.md`) |
| 14 | **Documentation as the contract** | the agent builds *from* `docs/`, not from chat |
| 15 | **Metadata-driven controls** | tags/policies/contracts live in Gravitino/OpenAPI; the POC gate uses the configured asset/contract (dynamic resolution planned) |
| 16 | **DQ as measured evidence** | data and API checks write to one `dq_results` history, not to dashboards alone |
| 17 | **Control plane vs data plane** | Gravitino/GE/OpenAPI are not in the data path; the Spring gate is the PEP |
| 18 | **Async-first DQ** | production target: samples via Kafka; the POC gate is synchronous for low-QPS validation |
| 19 | **Fail-open/closed per endpoint** | policy is explicit per endpoint class, never silent |
| 20 | **Contract versioning** | OpenAPI version = GE suite version = `contract_version` in `dq_results` |
| 21 | **PII-safe sampling** | redact/tokenize before GE; no payloads in logs or audit |
| 22 | **Bounded code carve-out** | code only in `operational-api/` and `dq/gx-service/`; data path stays codeless |

## Anti-patterns explicitly rejected

| Anti-pattern | Why rejected |
|---|---|
| Hand-written Iceberg metadata | bypasses catalog atomicity; non-representative |
| Building a custom Kafka→Iceberg sink | mature connector exists |
| A bespoke catalog or query layer | Iceberg REST + Trino already solve it |
| "Big bang" platform build | the slice is deliberately thin |
| Assuming freshness | it is measured |
| Running full GE on every **high-QPS** request | latency and memory cost; POC is sync/low-QPS; use inline checks + async samples in production |
| Treating `UNKNOWN`/`STALE` as `PASS` | hides a control-plane outage; fail-open/closed must be explicit |
| Copying metadata when federation suffices | creates a second source of truth and drift |
| Using Gravitino as an API gateway or DQ engine | it is a metadata plane, not a PEP or execution engine |
| Blocking direct Trino queries without access control | enforcement belongs at the API path or Trino access control |
| Letting the GE suite and OpenAPI contract drift | version both with `contract_version`; test T16 |

## Deferred practices (not this POC)

Policy-as-code with OPA, FinOps tagging, multi-region/sovereignty, formal data mesh/product contracts, full OpenMetadata/DataHub deployment, full OpenLineage lineage, full SRE runbooks — deferred until the POC v2 slice is proven.
