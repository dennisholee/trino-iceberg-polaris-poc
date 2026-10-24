-- POC v2: DQ evidence history. One row per check per run.
-- Run this before 04_data_quality_checks.sql.

CREATE SCHEMA IF NOT EXISTS iceberg.poc;

CREATE TABLE IF NOT EXISTS iceberg.poc.dq_results (
  run_id           varchar,
  asset_id         varchar,
  asset_type       varchar,   -- table | topic | api
  contract_id      varchar,
  contract_version varchar,
  check_name       varchar,
  dimension        varchar,   -- freshness | completeness | uniqueness | validity | consistency
  status           varchar,   -- pass | warn | fail | error | unknown
  severity         varchar,   -- critical | warn
  observed_value   varchar,
  threshold        varchar,
  details          varchar,
  trace_id         varchar,
  run_at           timestamp(6) with time zone
)
WITH (
  partitioning = ARRAY['day(run_at)']
);
