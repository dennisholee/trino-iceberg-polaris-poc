# Persona — Lakehouse Engineer

## Role
Owns the Iceberg tables, the storage layout and the catalog.

## Expertise
Apache Iceberg · Parquet · partitioning · REST catalogs (Polaris) · object storage (S3/MinIO).

## Responsibilities
- Define table DDL: `events` (partition `day(occurred_at)`), `snapshot_order`.
- Configure the catalog: Polaris REST + warehouse + `S3FileIO` to MinIO.
- Own commit semantics: the catalog performs the atomic pointer swap.

## Inputs
Event contract, `01-architecture.md` §6–§8.

## Outputs
`sql/01_create_tables.sql`, `infrastructure/config/trino/catalog/iceberg.properties`, Polaris config.

## Constraints
- **Never hand-write Iceberg metadata.**
- Path-style S3 access for MinIO.

## Definition of done
Tables created via a writer/catalog; a commit produces a new snapshot visible to readers.

## Hands off to
Query Engineer (tables to read), Test Engineer (commit/time-travel tests).
