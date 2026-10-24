-- POC v2: data DQ checks for the event log and snapshot.
-- Run after 05_create_dq_results.sql. Each check writes one row to dq_results.

INSERT INTO iceberg.poc.dq_results
WITH run AS (
  SELECT current_timestamp AS run_ts,
         concat('data-dq-', cast(current_timestamp AS varchar)) AS run_id
),
dup_events AS (
  SELECT count(*) AS c
  FROM (SELECT event_id FROM iceberg.poc.events GROUP BY event_id HAVING count(*) > 1)
),
null_keys AS (
  SELECT count(*) AS c
  FROM iceberg.poc.events
  WHERE aggregate_id IS NULL OR correlation_id IS NULL OR seq IS NULL OR occurred_at IS NULL
),
seq_violations AS (
  SELECT count(*) AS c
  FROM (
    SELECT aggregate_id, seq,
           lag(seq) OVER (PARTITION BY aggregate_id ORDER BY occurred_at, seq) AS prev_seq
    FROM iceberg.poc.events
  )
  WHERE prev_seq IS NOT NULL AND seq <= prev_seq
),
max_seq AS (
  SELECT aggregate_id, max(seq) AS max_seq
  FROM iceberg.poc.events
  GROUP BY aggregate_id
),
reconciliation AS (
  SELECT count(*) AS c
  FROM (
    SELECT s.aggregate_id
    FROM iceberg.poc.snapshot_order s
    LEFT JOIN max_seq e ON s.aggregate_id = e.aggregate_id
    WHERE e.max_seq IS NULL OR s.version <> e.max_seq
    UNION ALL
    SELECT e.aggregate_id
    FROM max_seq e
    LEFT JOIN iceberg.poc.snapshot_order s ON e.aggregate_id = s.aggregate_id
    WHERE s.aggregate_id IS NULL
  )
),
correlation_gaps AS (
  SELECT count(*) AS c
  FROM (SELECT DISTINCT correlation_id FROM iceberg.poc.events) e
  LEFT JOIN (SELECT DISTINCT correlation_id FROM iceberg.poc.snapshot_order) s
    ON e.correlation_id = s.correlation_id
  WHERE s.correlation_id IS NULL
),
freshness AS (
  SELECT coalesce(
           date_diff('second', cast(max(occurred_at) AS timestamp), cast(current_timestamp AS timestamp)),
           0) AS c
  FROM iceberg.poc.events
),
snapshot_freshness AS (
  SELECT coalesce(
           date_diff('second', cast(max(watermark_at) AS timestamp), cast(current_timestamp AS timestamp)),
           0) AS c
  FROM iceberg.poc.snapshot_order
),
row_count AS (
  SELECT count(*) AS c FROM iceberg.poc.events
)
SELECT run.run_id, 'iceberg.poc.events' AS asset_id, 'table' AS asset_type,
       'event-contract' AS contract_id, 'event-contract-v1' AS contract_version,
       'events.event_id.unique' AS check_name, 'uniqueness' AS dimension,
       CASE WHEN dup_events.c = 0 THEN 'pass' ELSE 'fail' END AS status,
       'critical' AS severity, cast(dup_events.c AS varchar) AS observed_value,
       '0' AS threshold, 'Duplicate event_id in raw events' AS details,
       cast(null AS varchar) AS trace_id, run.run_ts AS run_at
FROM run CROSS JOIN dup_events
UNION ALL
SELECT run.run_id, 'iceberg.poc.events', 'table', 'event-contract', 'event-contract-v1',
       'events.keys.not_null', 'completeness',
       CASE WHEN null_keys.c = 0 THEN 'pass' ELSE 'fail' END, 'critical',
       cast(null_keys.c AS varchar), '0',
       'Null aggregate_id/correlation_id/seq/occurred_at', cast(null AS varchar), run.run_ts
FROM run CROSS JOIN null_keys
UNION ALL
SELECT run.run_id, 'iceberg.poc.events', 'table', 'event-contract', 'event-contract-v1',
       'events.seq.monotonic', 'consistency',
       CASE WHEN seq_violations.c = 0 THEN 'pass' ELSE 'fail' END, 'critical',
       cast(seq_violations.c AS varchar), '0',
       'Non-monotonic seq per aggregate', cast(null AS varchar), run.run_ts
FROM run CROSS JOIN seq_violations
UNION ALL
SELECT run.run_id, 'iceberg.poc.snapshot_order', 'table', 'snapshot-order', 'snapshot-order-v1',
       'snapshot.reconciliation', 'consistency',
       CASE WHEN reconciliation.c = 0 THEN 'pass' ELSE 'fail' END, 'critical',
       cast(reconciliation.c AS varchar), '0',
       'Snapshot version disagrees with max event seq, or an aggregate is missing',
       cast(null AS varchar), run.run_ts
FROM run CROSS JOIN reconciliation
UNION ALL
SELECT run.run_id, 'iceberg.poc.snapshot_order', 'table', 'snapshot-order', 'snapshot-order-v1',
       'snapshot.correlation.completeness', 'completeness',
       CASE WHEN correlation_gaps.c = 0 THEN 'pass' ELSE 'fail' END, 'critical',
       cast(correlation_gaps.c AS varchar), '0',
       'Correlation ids present in events but absent from snapshot_order',
       cast(null AS varchar), run.run_ts
FROM run CROSS JOIN correlation_gaps
UNION ALL
SELECT run.run_id, 'iceberg.poc.events', 'table', 'event-contract', 'event-contract-v1',
       'events.freshness', 'freshness',
       CASE WHEN freshness.c <= 300 THEN 'pass' ELSE 'fail' END, 'critical',
       cast(freshness.c AS varchar), '300',
       'Seconds since the latest event occurred_at', cast(null AS varchar), run.run_ts
FROM run CROSS JOIN freshness
UNION ALL
SELECT run.run_id, 'iceberg.poc.snapshot_order', 'table', 'snapshot-order', 'snapshot-order-v1',
       'snapshot.freshness', 'freshness',
       CASE WHEN snapshot_freshness.c <= 300 THEN 'pass' ELSE 'fail' END, 'critical',
       cast(snapshot_freshness.c AS varchar), '300',
       'Seconds since the latest snapshot watermark_at', cast(null AS varchar), run.run_ts
FROM run CROSS JOIN snapshot_freshness
UNION ALL
SELECT run.run_id, 'iceberg.poc.events', 'table', 'event-contract', 'event-contract-v1',
       'events.row_count', 'completeness',
       CASE WHEN row_count.c >= 1 THEN 'pass' ELSE 'fail' END, 'warn',
       cast(row_count.c AS varchar), '1',
       'Minimum raw event rows', cast(null AS varchar), run.run_ts
FROM run CROSS JOIN row_count;
