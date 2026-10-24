-- Run in Trino against the `iceberg` catalog (Polaris REST catalog + MinIO storage).
-- Table creation is a catalog operation: the writer/catalog owns the metadata.

CREATE SCHEMA IF NOT EXISTS iceberg.poc;

-- Raw event log — immutable, partitioned by event day (event time).
CREATE TABLE IF NOT EXISTS iceberg.poc.events (
  event_id        varchar,
  event_type      varchar,
  schema_version  integer,
  aggregate_id    varchar,     -- fold key
  correlation_id  varchar,     -- cross-aggregate stitch key
  seq             bigint,      -- monotonic per aggregate
  occurred_at     timestamp(6) with time zone,
  payload         map(varchar, varchar)
)
WITH (
  partitioning = ARRAY['day(occurred_at)']
);

-- Aggregate snapshot — the read model, one row per aggregate.
CREATE TABLE IF NOT EXISTS iceberg.poc.snapshot_order (
  aggregate_id   varchar,
  correlation_id varchar,
  version        bigint,       -- last applied seq (idempotency guard)
  status         varchar,
  total          decimal(18, 2),
  last_event_at  timestamp(6) with time zone,
  watermark_at   timestamp(6) with time zone
);
