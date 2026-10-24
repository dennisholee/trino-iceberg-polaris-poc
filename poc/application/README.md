# `application/` — capabilities (ports)

> **Documentation-only.** No code lives here in this slice; this folder defines the *capabilities* the system needs — the codeless analogue of ports.

Depends only on the event contract (`domain/`). Describes capabilities that a **binding** must provide — not interfaces to implement.

## Use cases

| Use case | Description | Capabilities used |
|---|---|---|
| `IngestDomainEvent` | publish a conformant event to the event transport | publish |
| `MaterialiseAggregateSnapshot` | fold the event log into `snapshot_*` | store, query, fold |
| `QueryAggregateByCorrelation` | return the aggregate(s) for a correlation id | query |
| `RegisterDataAssets` | register Kafka topics and Polaris/Iceberg tables with tags/policies | govern |
| `RegisterApiContracts` | register operational API endpoints and versions | govern |
| `EvaluateDataQuality` | run data and API DQ checks and publish evidence | observe |
| `EnforceApiDataQuality` | allow / warn / block an API response from contract + DQ status | enforce |
| `PublishDqResults` | persist DQ history and refresh the status cache | observe |

## Capability contracts

| Capability | Contract | Bound by (product) |
|---|---|---|
| publish | emit a conformant `DomainEvent` | Kafka producer (source connector / CLI) |
| store | append events durably, committing via the catalog | Iceberg Kafka Connect sink |
| catalog | resolve/commit table metadata | Iceberg REST catalog (Polaris) |
| query | run SQL, return rows | Trino |
| fold | derive the snapshot from the event log | Trino SQL (or another SQL engine) |
| govern | register assets/contracts; resolve tags/policies | Gravitino + OpenAPI registry |
| observe | execute DQ checks; publish evidence | Trino SQL + Great Expectations |
| enforce | decide allow / warn / block for an API response | Spring Boot `ApiDqGate` |

## Boundary

The **capability list** is the abstraction; the **product** providing each capability is a binding
(`adapters/`), selected by configuration. Swapping a product changes configuration or a binding —
never the event contract or the table layout.

**POC v2 code carve-out:** `govern` is configuration (Gravitino/OpenAPI); `observe` is Trino SQL plus
the Python GE service; `enforce` is the Spring `ApiDqGate`. The data-path capabilities remain
codeless (**D22**).
