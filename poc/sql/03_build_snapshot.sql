-- Materialise the aggregate snapshot (strategy S2) — see seq-03.
-- Idempotent: an aggregate is only overwritten when a newer event (higher seq) exists.

MERGE INTO iceberg.poc.snapshot_order s
USING (
  SELECT
    aggregate_id,
    max_by(correlation_id, seq) AS correlation_id,
    max(seq)                    AS version,
    max_by(event_type, seq)     AS status,
    max(occurred_at)            AS last_event_at
  FROM iceberg.poc.events
  GROUP BY aggregate_id
) e
ON s.aggregate_id = e.aggregate_id
WHEN MATCHED AND e.version > s.version THEN UPDATE SET
  correlation_id = e.correlation_id,
  version        = e.version,
  status         = e.status,
  last_event_at  = e.last_event_at,
  watermark_at   = current_timestamp
WHEN NOT MATCHED THEN INSERT
  (aggregate_id, correlation_id, version, status, last_event_at, watermark_at)
  VALUES (e.aggregate_id, e.correlation_id, e.version, e.status, e.last_event_at, current_timestamp);

-- Serve the aggregate by correlation id (mode 2 of retrieval).
SELECT *
FROM iceberg.poc.snapshot_order
WHERE correlation_id = 'txn-456';
