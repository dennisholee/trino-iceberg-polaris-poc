# `adapters/` — bindings

> **Documentation-only, plus configuration.** No application code lives here; this folder records which product *binds* each capability.

| Capability | Binding (product) | Realised as |
|---|---|---|
| publish | Kafka (source connector / `kcat`) | connection config / CLI |
| store | Iceberg Kafka Connect sink | `infrastructure/config/kafka-connect/iceberg-sink.json` |
| catalog | Polaris (Iceberg REST) | catalog config + CLI bootstrap |
| query · fold | Trino | `sql/*.sql` + Trino CLI |
| storage | MinIO (S3 API) | connector properties |
| govern | Gravitino + OpenAPI registry | `../infrastructure/config/gravitino/` + `../metadata/api/openapi.yaml` |
| observe — data | Trino SQL | `../sql/04_data_quality_checks.sql` |
| observe — API | Great Expectations | `../dq/gx-service/` (Python) |
| enforce | Spring Boot `ApiDqGate` | `../operational-api/` |
| transport | Kafka | `api-dq-samples`, `dq-results` (planned) |
| evidence | Iceberg `dq_results` | Trino DDL/inserts |

## Notes

- The Iceberg sink binding is **configuration** — the connector performs both the write and the catalog commit.
- Bindings must not embed business rules; those belong to the event contract (`domain/`) and the fold (`sql/`).
- Swapping a binding (Trino → another engine, Polaris → another REST catalog) changes configuration only.

## Code carve-out (POC v2)

Gravitino and the OpenAPI registry are **configuration**. `../dq/gx-service/` and
`../operational-api/` are **bounded code bindings** of the `observe` and `enforce` capabilities
(**D22**). They do not write Iceberg data; data DQ evidence is written to `dq_results` through
Trino, and API evidence persistence is planned for the async `dq-results` consumer.

## Rule

No binding may hand-write Iceberg metadata. Writes go through a writer that commits via the catalog.
