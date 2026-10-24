# Event Hub → Iceberg → Trino — Proof of Concept (v2: Data + Control Plane)

**POC v1 proves that domain events on Kafka can be landed as an open Iceberg table on object storage, catalogued by a REST catalog, and retrieved as an aggregate snapshot through Trino — using third-party components only. POC v2 adds a metadata, contract, data-quality and API-enforcement control plane around that proven data path.**

---

## What it proves

| Goal | Evidence |
|---|---|
| G1 End-to-end path | `seq-01`, `seq-04` run against the live stack |
| G2 Aggregate by `correlation_id` | `sql/02_query_by_correlation.sql` |
| G3 Catalog owns atomicity | `seq-02`; no hand-written Iceberg metadata |
| G4 Measured freshness | test T4 records the staleness breakdown |
| G5 Contract-first layer map | the layer folders below |
| G6 Hot-view vs record / build vs buy | `docs/05-aggregation-bake-off.md` |
| G7 Metadata federation (Kafka + Polaris/Iceberg, no copy) | **T11 pass** — `tests/RESULTS-WAVE1.md` |
| G8 Contracts/tags for data and API assets; policies for data assets | **T12 pass** — `tests/RESULTS-WAVE2.md`; OpenAPI + `asset_catalog` |
| G9 DQ across Trino and APIs | **T13 data + T14 API pass** — `tests/RESULTS-WAVE3.md`, `tests/RESULTS-WAVE4-5.md` |
| G10 API-boundary enforcement | **T15 pass** — `tests/RESULTS-WAVE4-5.md`; Spring `ApiDqGate` + headers |
| G11 Hybrid A vs Hybrid B decision | ops/latency evidence: sync gate 0.35–0.89 s warm; `tests/RESULTS-WAVE4-5.md` |

> **T17 status:** the data-path regression baseline is **blocked** by a paused Connect task plus an
> empty post-resume commit. T6/T9 pass, T1/T7 are partial; see
> [`tests/RESULTS-T17.md`](tests/RESULTS-T17.md).

Full objectives and KPIs: [`docs/00-goals-and-objectives.md`](docs/00-goals-and-objectives.md). POC v2 design: [`docs/06-metadata-and-dq.md`](docs/06-metadata-and-dq.md). Options/comparison: [`../docs/metadata-and-data-quality-options.md`](../docs/metadata-and-data-quality-options.md).

## Structure (contract-first: contracts · capabilities · bindings · runtime)

```
poc/
├─ domain/           # the event contract (documentation-only)
├─ application/      # capabilities / ports (documentation-only)
├─ adapters/         # bindings = configuration (documentation-only)
├─ metadata/         # OpenAPI contracts + GE suite conventions (config)
├─ dq/               # gx-dq-service (Python + Great Expectations) — code carve-out (D22)
├─ operational-api/  # Spring Boot API + ApiDqGate (PEP) — code carve-out (D22)
├─ infrastructure/   # docker compose + configuration
├─ tests/            # verification against the objectives
└─ docs/
   ├─ 00-goals-and-objectives.md
   ├─ 01-architecture.md
   ├─ 02-agent-driven-development.md
   ├─ 03-third-party-services.md
   ├─ 04-architecture-practices.md
   ├─ 05-aggregation-bake-off.md
   ├─ 06-metadata-and-dq.md
   ├─ agents/                       # expert personas
   └─ diagrams/                     # SVG sequence diagrams
```

**Artefact-reference rule:** an artefact may reference a *contract*, never another artefact's internals. Layers are *contracts · capabilities · bindings · runtime*.

## Documents

| Document | Purpose |
|---|---|
| [`docs/00-goals-and-objectives.md`](docs/00-goals-and-objectives.md) | goals, objectives, KPIs, non-goals |
| [`docs/01-architecture.md`](docs/01-architecture.md) | architecture + key designs |
| [`docs/02-agent-driven-development.md`](docs/02-agent-driven-development.md) | DeepSeek agent + multi-agent personas |
| [`docs/03-third-party-services.md`](docs/03-third-party-services.md) | reuse register (don't reinvent) |
| [`docs/04-architecture-practices.md`](docs/04-architecture-practices.md) | practices adopted |
| [`docs/05-aggregation-bake-off.md`](docs/05-aggregation-bake-off.md) | hot-view vs record, build vs buy |
| [`docs/06-metadata-and-dq.md`](docs/06-metadata-and-dq.md) | POC v2 control plane: metadata, contracts, DQ, API gate |
| [`../docs/metadata-and-data-quality-options.md`](../docs/metadata-and-data-quality-options.md) | options comparison and hybrid recommendation |

## Diagrams

| Diagram | Flow |
|---|---|
| [`diagrams/layer-contracts-and-bindings.svg`](docs/diagrams/layer-contracts-and-bindings.svg) | contracts, capabilities, bindings, runtime |
| [`diagrams/seq-01-event-ingestion.svg`](docs/diagrams/seq-01-event-ingestion.svg) | event ingestion |
| [`diagrams/seq-02-catalog-commit.svg`](docs/diagrams/seq-02-catalog-commit.svg) | atomic catalog commit |
| [`diagrams/seq-03-snapshot-materialisation.svg`](docs/diagrams/seq-03-snapshot-materialisation.svg) | snapshot materialisation |
| [`diagrams/seq-04-aggregate-retrieval.svg`](docs/diagrams/seq-04-aggregate-retrieval.svg) | retrieval by correlation id |
| [`diagrams/seq-05-replay-recovery.svg`](docs/diagrams/seq-05-replay-recovery.svg) | replay & recovery |
| [`diagrams/seq-06-metadata-federation.svg`](docs/diagrams/seq-06-metadata-federation.svg) | metadata federation (POC v2) |
| [`diagrams/seq-07-dq-gate.svg`](docs/diagrams/seq-07-dq-gate.svg) | DQ evidence and API gate (POC v2) |

## Run

```bash
cd poc/infrastructure

# POC v1 data path
docker compose --profile data up -d      # kafka · minio · polaris · postgres · trino · connect
# create tables, start the sink, produce events, query with Trino

# POC v2 full control plane
docker compose --profile full up -d      # + gravitino · gx-dq · operational-api
# bootstrap Gravitino, seed asset_catalog, run DQ, start the API, verify the gate

# Gravitino UI (OAuth client-credentials form; POC bootstrap principal):
#   http://localhost:8090/ui/login
#   client_id=root  client_secret=secret  scope=PRINCIPAL_ROLE:ALL
```

> The `data` and `full` profiles are implemented. The full profile needs **8–16 GB RAM**; 4 GB is insufficient for the data path plus Gravitino, GE and Spring.

See [`infrastructure/README.md`](infrastructure/README.md) for wiring details.

## Non-goals

**POC v1:** multi-engine, HA, SSO, BigQuery interop, cost optimisation, compaction automation.

**POC v2:** replacing Polaris, deploying OpenMetadata/DataHub, Kafka Schema Registry, full cross-system lineage, HA/SSO, data-masking enforcement, full GE on every high-QPS request (POC gate is sync/low-QPS), blocking direct Trino queries, production-grade DQ.

The data path remains codeless. The only code is the bounded carve-out in `operational-api/` and `dq/gx-service/` (**D22**).
