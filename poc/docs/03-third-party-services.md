# Third-Party Services — Reuse, Don't Reinvent

**Every reusable capability in this slice already exists as a maintained third-party component. The POC composes them; the only application code is the bounded API gate and GE service (D22).**

---

## 1. Reuse register

| Capability | Reused component | Interface we consume | Not building |
|---|---|---|---|
| Event transport | **Apache Kafka** (KRaft) | topic produce/consume | a broker |
| Kafka → Iceberg writer | **Iceberg Kafka Connect sink** (`org.apache.iceberg.connect.IcebergSinkConnector`) | connector config + control topic | a custom sink |
| JSON → columns | Connector **SMTs** (`JsonToMapTransform`, `CopyValue`) | transform config | a parser |
| Fold (events → snapshot) | **Trino SQL `MERGE`** (default) or **Flink SQL** | SQL + scheduler | a custom aggregator |
| Table format | **Apache Iceberg** (via the sink) | Iceberg tables | a format |
| Catalog | **Apache Polaris** (REST) | Iceberg REST API | a catalog |
| Object storage | **MinIO** | S3 API | storage |
| Query engine | **Trino** (+ Iceberg connector) | SQL | a query engine |
| Query client | `trino` Python client | DB-API | an HTTP client |
| Metadata federation | **Apache Gravitino** | REST API + catalogs | a metadata lake |
| API contract registry | **OpenAPI 3.1 + Git** | spec files | a contract language |
| Data DQ | **Trino SQL** | SQL | a SQL engine |
| API DQ | **Great Expectations** | Python API / HTTP | an expectation engine |
| API gate (PEP) | **Spring Boot** | HTTP / Actuator | a DQ engine (thin gate only) |
| DQ status cache | **Caffeine** (Redis optional) | cache API | a cache |
| Resilience | **Resilience4j** | timeout / circuit breaker | a resilience library |
| Metrics | **Micrometer + Prometheus** | metrics | an observability stack |
| Event production (POC) | Kafka Connect **source connector** or `kcat` CLI | connector config / CLI | a producer application |
| Test data | `faker` | generation | hand-written fixtures |
| Local environment | **Docker Compose** | compose spec | bespoke setup |
| Integration testing (thin harness) | SQL assertions via **Trino CLI** + shell | CLI | a test framework |
| Config/secrets | `.env` + compose env | — | a config service |

## 2. Integration contracts (the boundaries we configure)

| Boundary | Configured in | Key properties |
|---|---|---|
| Kafka | `infrastructure/config/` | bootstrap servers, topic, key = `aggregate_id` |
| Connect sink | `infrastructure/config/kafka-connect/iceberg-sink.json` | connector class, catalog, tables, SMTs, commit interval |
| REST catalog | `iceberg-sink.json` + `trino/catalog/iceberg.properties` | URI, warehouse, credential |
| Object storage | both | `s3.endpoint`, `s3.path-style-access` |
| Trino | `infrastructure/config/trino/catalog/iceberg.properties` | `iceberg.catalog.type=rest`, URI, warehouse |
| Gravitino | `infrastructure/config/gravitino/` | entity store, Kafka/Iceberg catalogs, tags/policies |
| API contract | `metadata/api/openapi.yaml` | endpoints, request/response schemas, version |
| API DQ | `metadata/suites/` + `dq/gx-service/` | suite mapping, `asset_id`/`contract_version` (Kafka async planned) |
| API gate | `operational-api/` | `ApiDqGate`, sync GE, headers (cache/classes planned) |

## 3. What we own (thin)

| Owned | Why it must be ours |
|---|---|
| Event contract (envelope + payload) | it encodes *our* domain model |
| Aggregate/snapshot definition | our read model |
| Retrieval SQL | our access pattern |
| Connector **configuration** | wiring, not code |

## 4. Rule

> If a capability appears in §1, the POC **must not** implement it. Any proposal to build one requires an explicit ADR.

> **Codeless carve-out:** the **data path** is codeless. A thin test harness (SQL/shell assertions) is permitted — declared in `tests/README.md`. POC v2 adds **D22**: a bounded code carve-out for `operational-api/` (Spring gate) and `dq/gx-service/` (Python GE). No DQ engine, metadata lake, catalog or query engine is built.

## 5. Swappable, not fixed

The fold engine — and the query engine, and the catalog — are **implementations of a contract**, not commitments:

| Concern | Contract | Default | Alternatives |
|---|---|---|---|
| Fold | the snapshot table | Trino SQL `MERGE` | Flink SQL · Spark SQL · ksqlDB · RisingWave |
| Catalog | Iceberg REST spec | Polaris | Nessie · Glue · Unity · S3 Tables |
| Query | Iceberg tables | Trino | Spark · Flink · DuckDB |
| Metadata plane | assets/tags/policies | Gravitino | OpenMetadata · DataHub |
| Data DQ | SQL checks | Trino SQL | dbt tests · Soda · GE |
| API DQ | payload/contract checks | Great Expectations | Java-native validators · Soda · OpenMetadata DataFrameValidator |
| API gate | allow/warn/block decision | Spring `ApiDqGate` | APISIX/Kong/Envoy + OPA |
| Evidence store | DQ history | Iceberg `dq_results` | OpenMetadata/DataHub + Iceberg |

Swapping any of them changes **configuration or a binding** — never the event contract or the table layout.

## 6. Control-plane limits (POC v2)

| Gravitino does **not** | Consequence |
|---|---|
| copy metadata | it federates live sources; a source outage affects metadata reads |
| capture Kafka payload schemas | the domain contract / Schema Registry remains the schema source (**D24**) |
| provide a DQ engine | Trino SQL / GE execute checks; Gravitino stores metadata and latest stats |
| model API endpoints as first-class assets | the OpenAPI registry + `asset_catalog` bridge API assets |
| enforce custom policies | the operational API gate evaluates them (**D19**) |
| authenticate to Polaris with static catalog credentials | the REST backend forwards the caller's Bearer token; production needs an IdP (**D26**) |

| Great Expectations does **not** | Consequence |
|---|---|
| run as a JVM library | it runs as a separate Python service (**D20**) |
| act as a catalog or API gateway | metadata stays in Gravitino/OpenAPI; enforcement stays in Spring |
| block API responses | the Spring gate reads GE results and enforces (**D19**) |
| act as a streaming engine | use sampling / batch checkpoints, not per-event processing |
| natively validate deeply nested JSON | flatten or validate JSON Schema in Java / a custom expectation |
