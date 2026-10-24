# Gravitino bootstrap — POC v2 metadata plane

This directory stands up **Gravitino as a metadata plane** beside Polaris. It does not
replace Polaris and it does not copy metadata.

## Order

Run from `poc/infrastructure`:

```bash
# 1. Build the Gravitino image with the PostgreSQL driver + Polaris token validator.
docker compose --profile full build gravitino

# 2. Start the dependencies first (Gravitino needs the schema to exist).
docker compose --profile full up -d postgres polaris kafka

# 3. Create the Gravitino database/schema (safe on an existing pg-data volume).
./config/gravitino/bootstrap/00-init-db.sh

# 4. Start Gravitino.
docker compose --profile full up -d gravitino

# 5. Register the metalake + Kafka/Iceberg catalogs.
./config/gravitino/bootstrap/01-metadata.sh

# 6. Verify federation.
./config/gravitino/bootstrap/02-verify.sh

# 7. Create tags/policies and verify inheritance.
./config/gravitino/bootstrap/03-tags-policies.sh
```

If the `pg-data` volume is fresh, the Postgres entrypoint runs
`02-gravitino-db.sql` automatically; step 3 is still safe and handles existing volumes.

The scripts are re-runnable: `03-tags-policies.sh` detects existing attachments (it forces
`details=true` on Gravitino list calls) and reports `already attached` instead of failing.

## Authentication

Gravitino's `lakehouse-iceberg` REST backend uses `UserPrincipalForwardingAuthManager`: it forwards
the **caller's Bearer token** to Polaris. Anonymous/simple calls therefore fail with
`NotAuthorizedException`. The bootstrap scripts:

1. obtain a Polaris token with `client_credentials` (`POLARIS_CLIENT_ID` / `POLARIS_CLIENT_SECRET`,
   default `root` / `secret`; `POLARIS_SCOPE`, default `PRINCIPAL_ROLE:ALL`);
2. send it as `Authorization: Bearer <token>` to Gravitino.

Polaris JWTs have no `aud` claim, so Gravitino's built-in `StaticSignKeyValidator` rejects them. The
custom image adds a **spike-only** `PolarisTokenValidator` that verifies the RS256 signature, issuer
`polaris` and the `active` claim. This is not a production authentication design; production should
use an identity provider/token broker with audience-bound tokens.

Override endpoints if needed:

```bash
POLARIS_URL=http://localhost:8181 \
POLARIS_CLIENT_ID=root \
POLARIS_CLIENT_SECRET=secret \
POLARIS_SCOPE=PRINCIPAL_ROLE:ALL \
./config/gravitino/bootstrap/01-metadata.sh
```

## What is created

| Object | Value |
|---|---|
| Metalake | `poc` |
| Kafka catalog | `kafka` → `kafka:9092`, topic `domain-events` |
| Iceberg catalog | `iceberg` → `http://polaris:8181/api/catalog`, warehouse/catalog `poc` |
| Gravitino entity store | PostgreSQL database `gravitino`, schema `gravitino` |
| Audit | enabled (`gravitino.audit.enabled=true`) |
| Authorization | disabled for the POC |

The Iceberg catalog is a **REST proxy** (`catalog-backend=rest`) to Polaris. Gravitino forwards the
**caller's** Polaris Bearer token; the bootstrap scripts acquire it. It does not copy table metadata.

## Troubleshooting

- **Gravitino won't start** — check `docker compose logs gravitino`. The container runs with
  `SKIP_CONFIG_REWRITE=true` and reads the mounted `config/gravitino/gravitino.conf`.
- **PostgreSQL driver missing** — the custom image places
  `postgresql-42.7.4.jar` in `/opt/gravitino/jdbc-drivers/`; the entrypoint symlinks it into
  `/opt/gravitino/libs/`. Verify with
  `docker compose exec gravitino ls -l libs/postgresql-*.jar`.
- **Postgres schema missing** — run `00-init-db.sh`; do not hand-write the schema.
  The official script is `config/postgres/init/gravitino/schema-1.3.0-postgresql.psql`,
  copied verbatim from Gravitino v1.3.1 (`scripts/postgresql/schema-1.3.0-postgresql.sql`).
- **Polaris federation fails with `NotAuthorizedException`** — ensure the Gravitino request carries a
  Polaris Bearer token (the scripts do). Static `gravitino.bypass.credential` / `scope` are
  overwritten by `UserPrincipalForwardingAuthManager`. Confirm the spike validator is on the
  classpath (`docker compose exec gravitino ls -l libs/polaris-token-validator.jar`) and that the
  `defaultSignKey` in `gravitino.conf` matches Polaris's signing public key.
- **No Iceberg tables** — the data path has not run. Create the Trino tables, register the
  sink, produce events, then re-run `02-verify.sh`.
- **Web UI login 404 / undefined token URL** — `GET /configs` must expose both
  `gravitino.authenticator.oauth.serverUri` and `gravitino.authenticator.oauth.tokenPath`; the UI
  concatenates them. Both are set in `config/gravitino/gravitino.conf`. `serverUri` must be
  **browser-reachable** (`http://localhost:8181`), not the Docker DNS name (`http://polaris:8181`).
- **Web UI login blocked by CORS or 406** — the browser posts the client-credentials form
  cross-origin to Polaris. The UI's global `Accept: application/vnd.gravitino.v1+json` header is not
  produced by Polaris' token endpoint (**406**), and the browser needs CORS headers. The compose
  `polaris-proxy` (nginx on **8181**) rewrites `Accept` for
  `/api/catalog/v1/oauth/tokens` and supplies `access-control-allow-origin:
  http://localhost:8090`. Polaris is reached internally at `polaris:8181` and directly on host
  **8182**. After login, the UI calls `GET /api/authn/me` on Gravitino with the bearer token.
- **Port 8090** — Gravitino Web UI/API; Polaris is 8181 (proxy; direct 8182); Trino is 8081.

This is a **time-boxed spike**: the goal is to prove that Gravitino can see the Kafka topic
and the Polaris Iceberg catalog without a metadata copy. If it succeeds, continue with tags,
policies and the DQ layers.
