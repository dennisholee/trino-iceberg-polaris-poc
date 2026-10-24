-- POC v2 demo helper: copy the sink table into the raw event contract table.
-- This makes the DQ checks run against the same events the sink wrote, without
-- changing the data path. Idempotent by event_id.
-- Run before 03_build_snapshot.sql when the raw events table is empty.

INSERT INTO iceberg.poc.events
SELECT
  k.event_id,
  k.event_type,
  k.schema_version,
  k.aggregate_id,
  k.correlation_id,
  k.seq,
  CAST(from_iso8601_timestamp(k.occurred_at) AS timestamp(6) with time zone) AS occurred_at,
  k.payload
FROM (
  SELECT
    event_id,
    event_type,
    schema_version,
    aggregate_id,
    correlation_id,
    seq,
    occurred_at,
    payload,
    row_number() OVER (PARTITION BY event_id ORDER BY seq DESC) AS rn
  FROM iceberg.poc.events_kafka
) k
LEFT JOIN iceberg.poc.events e ON k.event_id = e.event_id
WHERE k.rn = 1 AND e.event_id IS NULL;
