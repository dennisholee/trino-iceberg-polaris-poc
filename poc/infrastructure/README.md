# `infrastructure/` — runtime and configuration

Frameworks and drivers. Reproduces the data path with the `data` profile and the POC v2 control plane with the `full` profile.

## Stack

| Service | Image (verify/pin) | Role |
|---|---|---|
| `kafka` | `apache/kafka:latest` (KRaft) | event transport, topic `domain-events` |
| `minio` | `bitnamilegacy/minio:latest` (MinIO's community images were removed from Docker Hub) | S3-compatible object storage (`warehouse/` bucket) |
| `postgres` | `postgres:16` | Polaris metastore; POC v2 adds a separate Gravitino database/schema |
| `polaris` | `apache/polaris:latest` | Iceberg REST catalog |
| `polaris-proxy` | `nginx:1.27-alpine` | host-facing Polaris entry point on 8181; normalizes the Gravitino UI token `Accept` header and owns its CORS response |
| `trino` | `trinodb/trino:latest` | query engine (Iceberg connector) |
| `connect` | **custom build** — `iceberg-connect:local`, compiled from Iceberg source (D13) | Kafka Connect 8.0 (Java 17) + Iceberg sink plugin |
| `gravitino` | **custom build** — `gravitino-poc:1.3.1` (adds PostgreSQL driver + POC Polaris token validator) | metadata/control plane: Kafka topic + Polaris Iceberg metadata, tags/policies/statistics/audit |
| `gx-dq` | **custom Python image** | Great Expectations API DQ service (`/v1/validate`, Kafka worker) |
| `operational-api` | **custom Spring Boot image** | operational API + `ApiDqGate` (PEP) |
| `prometheus` / `grafana` | optional | DQ/gate metrics and dashboards |

> ⚠️ Image tags above are indicative — **pin and verify** them for your environment before relying on the stack.

## Configuration surfaces

| File | Binds |
|---|---|
| `config/kafka-connect/iceberg-sink.json` | Kafka → Iceberg sink (connector class, catalog, tables, SMTs, commit interval) |
| `config/trino/catalog/iceberg.properties` | Trino Iceberg connector → Polaris (REST) + MinIO |
| `config/polaris/application.properties` | Polaris server config for a non-Docker deployment (the compose stack passes the same settings as env vars — see the polaris service) |
| `config/polaris/keys/*.pem` | **stable RSA key pair** for the token broker (a POC artefact; use a secret manager in production) |
| `config/polaris/nginx.conf` | host-facing proxy on 8181: rewrites `Accept` for the UI token exchange and supplies CORS headers |
| `config/postgres/init/01-polaris-schema.sql` | pre-creates Polaris's metastore schema — Polaris does **not** create it |
| `docker-compose.yml` | service wiring, ports, volumes, env |
| `connect/Dockerfile` | multi-stage build: compiles the Iceberg sink runtime from the Apache source tarball and installs the jars into a Connect 8.0 (Java 17) plugin directory |

## Ports

| Service | Port |
|---|---|
| Kafka | 9092 |
| MinIO | 9000 (S3), 9001 (console) |
| Polaris (host-facing proxy) | 8181 |
| Polaris (direct, debugging) | 8182 |
| Trino | **8081** (host) → 8080 (container) — host 8080 is commonly taken |
| Kafka Connect | 8083 |
| Gravitino | 8090 |
| `gx-dq` | 8000 |
| `operational-api` | **8082** (avoid 8080/8081) |
| Prometheus / Grafana (optional) | 9090 / 3000 |

## Configuration surfaces (POC v2)

| File | Binds |
|---|---|
| `config/gravitino/gravitino.conf` | entity store, audit, authenticator/authorizer |
| `config/gravitino/bootstrap/` | metalake, Kafka/Iceberg catalogs, tags, policies |
| `../metadata/api/openapi.yaml` | operational API contract |
| `../metadata/suites/*.json` | GE expectation suites |
| `../operational-api/src/main/resources/application.yml` | Spring gate, GE client |
| `../dq/gx-service/` | Python service image, endpoint, suite loader |

> These surfaces are implemented in POC v2. The run order below follows the waves used to build them.

## Run order

1. `docker compose build connect` — **compiles the Iceberg connector from source** (~6.5 min; the build is memory-hungry, so on a small host stop the other JVMs first with `docker compose stop kafka polaris trino`).
2. `docker compose --profile data up -d` (Kafka, MinIO, Postgres, Polaris, Trino, Connect). For the full control plane, use `--profile full` (adds Gravitino, GE and the Spring API).
3. Create the MinIO bucket `warehouse`. This MinIO build has **no console** (only 9000 listens), so it is
   created with `mc` inside the container:

   ```bash
   docker compose exec -T minio sh -c '
     mc alias set local http://127.0.0.1:9000 minio minio123 &&
     mc mb --ignore-existing local/warehouse'
   ```
4. **Bootstrap the Polaris metastore once** with the Admin Tool — this creates the tables *and* the realm/principal in Postgres (the schema itself must already exist, see `config/postgres/init`):

   ```bash
   docker run --rm --network infrastructure_default \
     --env polaris.persistence.type=relational-jdbc \
     --env quarkus.datasource.jdbc.url="jdbc:postgresql://postgres:5432/polaris?currentSchema=polaris_schema" \
     --env quarkus.datasource.username=polaris --env quarkus.datasource.password=polaris \
     apache/polaris-admin-tool:latest bootstrap -r POLARIS -c POLARIS,root,secret
   ```

   On an existing `pg-data` volume the schema was created on first init; otherwise run
   `CREATE SCHEMA IF NOT EXISTS polaris_schema;` once as shown above.
5. Create the catalog `poc` via the **Management API** (the Iceberg REST path has no create-catalog
   operation). The payload is [`config/polaris/catalog.poc.json`](config/polaris/catalog.poc.json);
   the creating principal is the one that can use it, which is why Trino and the sink both run as `root`:

   ```bash
   TOKEN=$(curl -sS -X POST http://localhost:8181/api/catalog/v1/oauth/tokens \
     -d grant_type=client_credentials -d client_id=root -d client_secret=secret \
     -d scope=PRINCIPAL_ROLE:ALL | jq -r .access_token)

   curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
     -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
     --data @config/polaris/catalog.poc.json \
     http://localhost:8181/api/management/v1/catalogs     # → 201
   ```

   A different principal needs a catalog role and a grant before it can see the catalog.
6. Create tables via Trino (`../sql/01_create_tables.sql`).
7. Register the sink connector (`iceberg-sink.json`) and **resume** it:
   `curl -X PUT http://localhost:8083/connectors/iceberg-events-sink/resume`. A task can report
   `RUNNING` while its target state is `PAUSED`; `resume` is idempotent. Verify the consumer lag drains.
8. Produce events → query (`../sql/02_query_by_correlation.sql`).
9. **POC v2 / metadata plane:** build Gravitino and start the dependencies:
   `docker compose --profile full build gravitino`
   `docker compose --profile full up -d postgres polaris kafka`
10. Initialize the Gravitino entity store: `./config/gravitino/bootstrap/00-init-db.sh`.
11. Start Gravitino: `docker compose --profile full up -d gravitino`.
12. Register and verify the metadata plane:
    `./config/gravitino/bootstrap/01-metadata.sh`
    `./config/gravitino/bootstrap/02-verify.sh`
13. **POC v2 / data DQ:** asset catalog, check history and table status (Trino + MinIO must be up):

    ```bash
    docker compose --profile full up -d minio trino
    docker compose exec -T trino trino --catalog iceberg --schema poc < ../sql/05_create_dq_results.sql
    docker compose exec -T trino trino --catalog iceberg --schema poc < ../sql/06_asset_catalog.sql
    # demo seed if the raw contract table is empty (sink wrote events_kafka)
    docker compose exec -T trino trino --catalog iceberg --schema poc < ../sql/08_seed_events_from_sink.sql
    docker compose exec -T trino trino --catalog iceberg --schema poc < ../sql/03_build_snapshot.sql
    docker compose exec -T trino trino --catalog iceberg --schema poc < ../sql/04_data_quality_checks.sql
    docker compose exec -T trino trino --catalog iceberg --schema poc < ../sql/07_update_asset_status.sql
    ```

14. **POC v2 / API DQ:** start the GE service and the Spring gate:

    ```bash
    docker compose --profile full up -d gx-dq operational-api
    curl -s http://localhost:8000/health
    curl -i http://localhost:8082/v1/orders/txn-JDBC
    curl -i 'http://localhost:8082/v1/orders/txn-JDBC?scenario=bad'
    ```

    Expected: the first request is `200` with `X-DQ-Status: pass`; the bad scenario is `503` with
    `X-DQ-Status: fail`. If `gx-dq` is stopped, the gate fails closed with `X-DQ-Status: unknown`.

> Gravitino's API is OAuth-protected in POC v2. The bootstrap scripts obtain a Polaris bearer token and send it to Gravitino; see `config/gravitino/bootstrap/README.md`.

## Known friction

- **Polaris bootstrap/RBAC** — budget the most time here.
- **Polaris persistence** — three separate traps, all handled: the default metastore is **`in-memory`** (test-only, loses everything on restart); the schema must **pre-exist** because Polaris never creates it; and a mounted `application.properties` is **ignored**, so settings go in as **environment variables**.
- **Polaris signing keys** — without a mounted key pair Polaris mints an ephemeral RSA key at each start, which **invalidates every token already issued**. Long-lived clients (the Kafka sink) then fail with `NotAuthorizedException` after any restart.
- **Connect image** — the connector has **no published binary** (D13), so the image builds it from the Apache source tarball. Three traps, all hit and fixed: the worker must run **Java 17+** (Connect 7.x runs Java 11 → `UnsupportedClassVersionError`); the jars must sit **flat** in a plugin directory (the distribution nests them under `lib/`); and the sink's `S3FileIO` needs the **AWS credential env vars** (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION`).
- **`value.converter` must be `StringConverter`** — `JsonToMapTransform` parses the raw JSON itself and rejects a deserialized record.
- **Credential vending** — disabled for the POC; static MinIO keys are used.
- **Host RAM** — 4 GB is tight for six JVMs. The default Connect heap plus Trino and the control plane **OOM-killed Trino** on 2026-10-18; compose now caps Connect with `KAFKA_HEAP_OPTS=-Xmx768m`, but the full stack still needs **8–16 GB**.
- **Connect paused/empty-commit trap** — on 2026-10-18 the sink task reported `RUNNING` while its
  **target state was `PAUSED`**; a consumer group can be `Stable` with constant lag in that state.
  `PUT /connectors/iceberg-events-sink/resume` drained the lag and wrote one event, but a later batch
  consumed without a visible snapshot/rows (coordinator reported a table commit). A side-by-side 8.1
  worker reproduced the pause and then failed with `Coordinator unexpectedly terminated`. Always
  `resume` after registration/restart, assert lag drains, and reset the connector/control state
  deliberately; T1–T10 remain blocked. See `../tests/RESULTS-T17.md` and **O15**.
- **Compose profiles and `restart`** — `docker compose restart` **with no service argument** exits 0 without restarting anything when every service is in a profile; the container's `StartedAt` does not move. Naming a service works (`docker compose restart polaris`); use `docker compose --profile data restart` (or `docker restart $(docker compose --profile data ps -q)`) for the whole stack. Any restart assertion that only compares row counts will pass trivially if nothing restarted.
- **Gravitino UI login** — `/ui/login` reads `GET /configs` and posts client credentials to
  `gravitino.authenticator.oauth.serverUri + …tokenPath`. Both keys are set in
  `config/gravitino/gravitino.conf`; `serverUri` is `http://localhost:8181` because the browser, not
  the container, resolves it. The UI sets a global `Accept: application/vnd.gravitino.v1+json`
  header, which Polaris' token endpoint answers with **406 Not Acceptable**; `curl` does not send it,
  so it falsely appears healthy. `polaris-proxy` (nginx on 8181) rewrites `Accept` for
  `/api/catalog/v1/oauth/tokens` to `application/json` and supplies the CORS headers for
  `http://localhost:8090`. Polaris itself remains on the compose network at `polaris:8181` and is
  exposed directly on host **8182** for debugging.
- **POC v2 RAM** — Gravitino + GE + Spring + the existing six JVMs will exceed 4 GB. Recommend **8–16 GB**, or use compose profiles (`data` vs `full`) and set `GRAVITINO_MEM`, `GX_DQ_MEM`, and Spring `-Xmx`.
- **Gravitino → Polaris auth** — the `lakehouse-iceberg` REST backend sets `UserPrincipalForwardingAuthManager`, which forwards the **caller's Bearer token**. Static `credential`/`scope` catalog properties are overwritten. The bootstrap scripts obtain a Polaris token and send it to Gravitino. Polaris JWTs have no `aud` claim, so the custom image adds a **spike-only** `PolarisTokenValidator` that checks the RS256 signature, issuer and `active` flag. Do not ship this validator to production; use an IdP/token broker with audience-bound tokens.
- **Gravitino Postgres** — use the official schema script and a **separate database/schema**; do not reuse `polaris_schema`. The official script is `config/postgres/init/gravitino/schema-1.3.0-postgresql.psql` (copied from Gravitino v1.3.1).
- **Python/JVM split** — GE is Python-only; `gx-dq` is a separate service. Do not embed Python in the Spring container.
- **PII** — API samples must be redacted/tokenized before leaving the JVM; never log payloads in GE or the gate.
