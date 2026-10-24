-- POC v2: refresh the latest DQ status in the asset index.
-- Run after 04_data_quality_checks.sql.

MERGE INTO iceberg.poc.asset_catalog t
USING (
  WITH latest AS (
    SELECT asset_id, max(run_at) AS run_at
    FROM iceberg.poc.dq_results
    GROUP BY asset_id
  ),
  statuses AS (
    SELECT
      d.asset_id,
      d.run_at,
      max(CASE d.status
            WHEN 'fail'  THEN 4
            WHEN 'error' THEN 3
            WHEN 'warn'  THEN 2
            WHEN 'pass'  THEN 1
            ELSE 0
          END) AS status_rank
    FROM iceberg.poc.dq_results d
    JOIN latest l ON d.asset_id = l.asset_id AND d.run_at = l.run_at
    GROUP BY d.asset_id, d.run_at
  ),
  ranked AS (
    SELECT
      asset_id,
      status_rank,
      run_at,
      row_number() OVER (PARTITION BY asset_id ORDER BY status_rank DESC, run_at DESC) AS rn
    FROM statuses
  )
  SELECT
    asset_id,
    CASE status_rank
      WHEN 4 THEN 'fail'
      WHEN 3 THEN 'error'
      WHEN 2 THEN 'warn'
      WHEN 1 THEN 'pass'
      ELSE 'unknown'
    END AS status,
    run_at
  FROM ranked
  WHERE rn = 1
) s
ON t.asset_id = s.asset_id
WHEN MATCHED THEN UPDATE SET
  dq_status   = s.status,
  last_run_at = s.run_at;
