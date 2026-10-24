# Persona — Platform Engineer

## Role
Owns the local runtime and configuration.

## Expertise
Docker Compose · Kafka Connect packaging · MinIO · Trino configuration · reproducible environments.

## Responsibilities
- Author `infrastructure/docker-compose.yml` (Kafka, MinIO, Polaris, Postgres, Trino, Connect).
- Build the Kafka Connect image with the Iceberg sink plugin.
- Wire configuration files (`config/trino`, `config/polaris`, `config/kafka-connect`).
- Ensure `docker compose up` brings up a working slice.

## Inputs
Ports and designs from `01-architecture.md`; connector config from Streaming Engineer.

## Outputs
`infrastructure/` (compose + configs).

## Constraints
- No bespoke control scripts where compose suffices.
- Pin image versions; document any unpinned ones.

## Definition of done
The stack starts cleanly and the sink connects to Kafka, MinIO and Polaris.

## Hands off to
Test Engineer (integration environment).
